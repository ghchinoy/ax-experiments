# Architectural Friction Report: Correlation IDs, Swarm Lineage, and Observability in AX

> **Document Status**: Post-Implementation Analysis & RFC  
> **Author**: Hussain Chinoy (`ghchinoy@google.com`)  
> **Target Audience**: AX and Agent Substrate committers, architecture working group, and platform engineers  
> **Context**: Derived from building the Apple Container swarm replayer (`viz/`) and multi-agent recipes (`swarm/`) on AX `main` (`d0bc38b`)

---

## 1. Executive Summary

Building the multi-agent swarm recipes (`01-hello-swarm` through `07-suspend-resume`) and the Lit/`force-graph`/Cytoscape visualizer exposed a fundamental architectural blind spot in AX's current design:

**AX excels at low-level infrastructure lifecycle management (provisioning, sandboxing, IP assignment, suspension, and deletion), but it is completely blind to swarm intent, task lineage, command execution, and inter-agent communication.**

Today, an orchestrator can spawn 8 parallel microVM tasks, but AX views them as 8 completely isolated, unrelated records in Redis. When an agent in Container A produces data that is piped into Container B, that data flow happens entirely outside AX's knowledge. Furthermore, because `ax ssh` dials the guest daemon directly over the container's private IP, **command executions inside sandboxes leave zero record in AX's event log or controller**.

This report analyzes these friction points and outlines a concrete, phased proposal for:
1. First-class task lineage and correlation IDs in `v1alpha1.Task`.
2. Standard W3C TraceContext propagation.
3. Observability hooks for guest executions.
4. AX-mediated swarm communication channels (eliminating ad-hoc host pipes).

---

## 2. The Current Friction: What We Discovered Building Swarms

### Friction Point 1: The Lifecycle / Execution Disconnect

In AX, a Task's status machine reports on **infrastructure state**, not **computational progress**:

```
[ What AX Knows ]                       [ What the Agent is Doing ]
Phase: Pending                          Container created
Phase: Running                          ax-task-runner boots metadata daemon on :80
Ready: True (WorkspaceReady)             /workspace initialized (git cloned)
                                        ─── AX TELEMETRY GOES BLIND HERE ───
                                        Task command starts executing
                                        Agent calls Gemini / models
                                        Subprocesses spawn / fail
                                        Command exits with code 1
                                        ─────────────────────────────────────
Phase: Running (still!)                 Container stays alive for post-mortem
```

Because `ax-task-runner` deliberately keeps the container alive after the command exits so developers can inspect `/workspace` via `ax ssh`, **the control plane does not know whether a task's workload is actively computing, idle, or crashed**. As noted in open upstream issue [#346](https://github.com/google/ax/issues/346), tasks remain `Running` and `Ready=True` indefinitely after their command exits.

### Friction Point 2: `ax ssh` Completely Bypasses the Control Plane

In our multi-agent recipes (e.g. Code Review Panel, Debate, Map-Reduce), the orchestrator triggers work inside the sandbox using `ax ssh`:

```
Host CLI ───1. GetTask(task)───> ax-server (resolves WorkerIP: 192.168.64.x)
   │
   └──────────2. Direct gRPC guest.Dial("192.168.64.x:80") ───> Apple Container
                 (ProcessService.StartProcess / Exec)
```

**Consequence**: `ax-server`, `ax-controller`, and Redis record **nothing** about the execution. There is no log entry, no event published, and no timestamp recorded when an agent executes a command. To build our visualization replay, we had to introduce an out-of-band recipe marker stream (`lib.sh -> trace_event`) because AX core emitted zero signals for remote execution.

### Friction Point 3: Flat Tasks with Zero Lineage or Causality

When building the **06 Map-Reduce Swarm** (3 Mappers + 1 Reducer):
- The 4 tasks (`map-topic-1`, `map-topic-2`, `map-topic-3`, `reduce-synthesis`) are logically part of one distributed transaction.
- In AX's store, they are 4 disconnected keys: `ax:task:default:map-topic-1`, `ax:task:default:map-topic-2`, etc.
- There is no field in `TaskSpec` or `TaskStatus` to indicate:
  - Who spawned this task? (`parent_task_id`)
  - What swarm/session does it belong to? (`correlation_id`)
  - Is it a leaf node or a coordinator? (`root_task_id`)

If a developer runs `ax get tasks` during a multi-agent run, they see an unorganized list with no tree hierarchy. If a parent task fails or is cancelled, AX has no mechanism to identify or clean up its orphaned children.

### Friction Point 4: No W3C TraceContext or OpenTelemetry Propagation

AX has no mechanism to inject distributed tracing context into sandboxes:
- No `traceparent` (W3C standard) or `tracestate` headers are passed through task environment variables.
- An agent script running inside Container A calling a model or an MCP tool cannot correlate its spans with the AX task turn that spawned it.
- End-to-end distributed tracing across a swarm of agents is impossible without manually constructing custom tracing wrappers.

### Friction Point 5: Ad-Hoc Host-Mediated Swarm Piping

In recipe `05-debate.sh`, we wanted the Critic agent to receive the Proposer agent's output. Because AX lacks an inter-actor messaging primitive, we had to implement a manual host relay:

```bash
PROPOSAL="$(ssh_task debate-proposer python3 /usr/local/bin/agent.py)"
REBUTTAL="$(ssh_task debate-critic sh -c "AGENT_PROMPT='...$PROPOSAL' python3 /usr/local/bin/agent.py")"
```

The host laptop became an accidental message broker. If the host network hiccups, the entire swarm fails. There is no durable mailbox, message queue, or pub/sub topic provided by AX for actors in the same atespace to communicate directly.

---

## 3. Concrete Proposals for AX Core

To transform AX from an isolated container launcher into a true **distributed agent orchestration runtime**, we propose five enhancements:

### Proposal 1: Add Lineage and Correlation to `v1alpha1.Task`

Extend `pkg/apis/v1alpha1/ax.proto`:

```protobuf
message TaskSpec {
  // Existing fields...
  string image = 1;
  repeated string command = 2;
  repeated EnvVar env = 3;
  ResourceReqs resources = 4;
  repeated WorkspaceRef workspaces = 5;
  bool debug = 6;

  // NEW: Distributed correlation and swarm lineage
  string correlation_id = 7;     // Caller-provided session/swarm trace ID
  string parent_task = 8;        // Name of the spawning parent task (if any)
  repeated string tags = 9;      // Semantic labels (e.g. ["role=mapper", "round=1"])
}

message TaskStatus {
  // Existing fields...
  string phase = 1;
  string id = 2;
  string actor = 3;
  string worker_ip = 4;
  
  // NEW: Lineage tracking
  string root_task = 8;          // Top-level coordinator task ID
  google.protobuf.Timestamp started_at = 9;
  google.protobuf.Timestamp finished_at = 10;
  int32 exit_code = 11;          // Exit code of spec.command (once completed)
}
```

**Benefits**:
- `ax get tasks --tree`: Renders a hierarchical tree of parent and child tasks.
- Cascade deletion: `ax delete task root-task --cascade` automatically tears down all children.
- Graph visualization tools can construct dependency DAGs without external markers.

---

### Proposal 2: Automatic W3C TraceContext Injection

The AX controller should treat distributed tracing as a first-class concern:
1. When a task is created without a `correlation_id`, generate a standard W3C TraceContext (`traceparent`).
2. When launching the container (via Substrate or `ate-local`), automatically inject standard environment variables into the guest:
   ```bash
   AX_CORRELATION_ID="c4b9-4810-8022"
   TRACEPARENT="00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
   TRACESTATE="ax=default:map-topic-1"
   AX_TASK_NAME="map-topic-1"
   AX_ATESPACE="default"
   ```
3. Any SDK (OpenTelemetry, `google-genai`, LangChain, ADK) running inside the container can automatically adopt the ambient `TRACEPARENT`, linking LLM spans and tool executions directly to the AX task.

---

### Proposal 3: Observable Guest Daemon (`ProcessService` Telemetry)

When `spec.debug: true` is enabled, `ax-task-runner` serves the guest `ProcessService` on port 80.

We propose adding an execution event hook inside `internal/guest` or `runner`:
- When `StartProcess` is invoked (e.g. by `ax ssh`), the runner emits an audit event to the metadata server:
  `POST /metadata/v1alpha1/ax/events` -> `{"kind": "exec.start", "pid": 1234, "cmd": ["uname", "-sm"]}`
- When the process terminates, it emits:
  `{"kind": "exec.end", "pid": 1234, "exit_code": 0, "duration_ms": 32}`
- These events are buffered and reflected in `TaskStatus.events` or streamed via `WatchTask`.

**Result**: Remote command execution becomes fully observable and auditable in the control plane.

---

### Proposal 4: AX-Mediated Swarm Mailbox / Channels

Instead of forcing developers to write ad-hoc bash relays, AX should leverage its existing Valkey/Redis infrastructure to provide an in-sandbox messaging primitive:

```
Container 1 (Proposer) ──POST /metadata/v1alpha1/channels/debate/messages──> ax-server
                                                                               │
                                                    Stores in Redis Stream     │
                                                                               ▼
Container 2 (Critic)   <──GET /metadata/v1alpha1/channels/debate/messages──── ax-server
```

- Each task can read and write to channels within its atespace using standard HTTP calls to `$AX_METADATA_URL`.
- AX handles persistence, ordering, and delivery.
- Every message automatically inherits the sender's `correlation_id` and task identity.

---

### Proposal 5: Structured JSON Streaming (`ax watch --format=json`)

Currently, `ax watch` outputs plain tabwriter text to `os.Stdout`:
`[Running   ] Phase: Running    Actor: local-task   WorkerIP: 192.168.64.x`

Adding a `--format=json` (or `jsonl`) flag would allow developer tooling, web visualizers, CI monitors, and IDE plugins to consume clean, typed event streams natively without writing custom scrapers or tapping directly into Redis:

```json
{"timestamp":"2026-09-26T12:20:49Z","atespace":"default","task":"map-1","phase":"Running","workerIP":"192.168.64.81","conditions":[{"type":"Ready","status":"True"}]}
```

---

## 4. Broader Value Beyond Visualization

Addressing this friction is not just about making nice Cytoscape or `force-graph` animations. It solves fundamental production requirements outlined in AX's own roadmap:

| Area | Value of Correlation IDs & Swarm Lineage |
|---|---|
| **Enterprise Audit & Governance** | Meet Google Platform governance requirements (Roadmap Section 4) by providing an immutable causal audit trail of which agent spawned which subtask and what tools were called. |
| **Token & Cost Attribution** | Attribute LLM token consumption and compute hours back to the root task or user session, rather than having disconnected leaf tasks incur un-attributable costs. |
| **Autonomic Swarm Management** | Detect deadlocks, stalled branches, or runaway loops in agent fan-outs. Automatically prune orphaned subtrees if a parent task fails or exceeds its budget. |
| **Resumption & Task Branching** | In Roadmap Section 2 ("Stateful Task Branching"), branching an actor into speculative execution paths requires tracking child branches from a shared state root. Lineage metadata is the foundational schema required for task branching. |

---

## 5. Conclusion & Next Steps

The `ate-local` implementation proves that running multi-agent swarms on macOS with native Apple containers is fast (~0.6s microVM launch, 0.70s readiness) and practical. 

However, as agent developers shift from running single tasks to coordinating swarms, AX must evolve its schema from a **flat task registry** to a **causally-linked agent orchestration mesh**.

We recommend presenting Proposals 1 and 2 (correlation IDs and `TRACEPARENT` injection) as a near-term RFC to the AX architecture working group, while exploring Proposal 4 (in-sandbox messaging channels) as a future Substrate ecosystem capability.
