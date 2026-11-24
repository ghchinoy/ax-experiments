# 4. How AX Differs from Agent Substrate & Grows into an Agentic Platform (`#724`, `#732`)

[Document 1](./01-substrate-and-ax-mental-model.md) introduced the two-plane split between Agent Substrate and AX, and [Document 2](./02-the-three-pivots.md) traced how AX converged on its `v0.4` task-orchestration contract (`#683`, `#688`, `#696`). In **[`google/ax#724`](https://github.com/google/ax/issues/724)** and **[`google/ax#732`](https://github.com/google/ax/pull/732)**, upstream frames the long-term boundary starkly: *besides task execution, AX and Agent Substrate are orthogonal projects*, and AX is being built as a **portable agentic platform** that runs the same way **inside Google, on customer clusters, and on-prem** (as well as locally on a developer laptop via [`ate-local`](./03-datacenter-to-laptop.md)).

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="diagrams/05-agentic-platform-evolution-dark.webp">
  <img alt="AX evolution from task orchestrator over Agent Substrate 1.0 to a 7-pillar agentic platform" src="diagrams/05-agentic-platform-evolution-light.webp">
</picture>

---

## 1. The Clean Layer Boundary: Orthogonal Outside Task Execution

The shortest way to separate the two projects is by **where they meet—and where they don't** ([`google/ax#732`](https://github.com/google/ax/pull/732)):

- **Agent Substrate is the compute runtime layer.** It schedules untrusted sandboxes (`Actor`s) onto pre-warmed `WorkerPool` Pods from immutable container classes (`ActorTemplate`s), restores them in `<100 ms`, suspends/resumes and checkpoints them (`Tag`s), routes inbound HTTP/gRPC traffic by logical ID (`atenet-router`), and mediates outbound network access and secret header injection (`atenet-egress`). It deliberately knows *almost nothing* about agents—no prompts, LLMs, sessions, memory, MCP tools, skills, or multi-agent graphs.
- **AX and Agent Substrate intersect *only* at task execution.** AX runs each `Task` on Substrate (`1 Task = 1 Actor`), and everything else in AX—declarative specs (`Task`, `Workspace`, `Model`, `Gateway`), runner/launcher contracts (`ax-runner` / `ax-launcher`, `#711`, `$AX_WORKSPACE` `#723`), sessions, memory, multi-task coordination, input steering, registries, models, and trajectory collection—is **orthogonal** to Substrate. Keeping that boundary narrow is also what lets AX stay portable across Google-internal infrastructure, customer Kubernetes clusters, on-prem environments, and zero-Kubernetes local runtimes (`ate-local`, `#712`).

### Responsibility Matrix

| Concern | Agent Substrate `1.0` (`ateapi/v1`) | AX (`ax.io/v1alpha1`) |
|---|---|---|
| **Core primitive** | `ActorTemplate`, `Actor`, `Tag`, `WorkerPool`, `EgressPolicy` | `Task`, `Workspace`, `Model`, `Gateway` (+ emerging `Session`, `Memory`, `Agent`) |
| **Isolation & scheduling** | gVisor / microVM sandboxes, OverlayFS image cache, `<100 ms` wake-on-request | Never schedules Pods or manages hypervisors; delegates execution via `Control` gRPC (`ate-local` swaps the backend locally) |
| **Lifecycle & state** | Actor states (`RESUMING`, `RUNNING`, `SUSPENDING`, `SUSPENDED`, `CRASHED`, `DELETING`, `REVERTING`), durable disk snapshots, future self-suspend (`substrate#450`) | Aligns `TaskState < 200` 1-to-1 to Substrate `ActorState` (`#731`), cold-start resume invariant (`#683`); leaves higher-level progress/completion to callers & agent protocols rather than server-side status polling (`#690`/`#743`) |
| **Network & secrets** | SPIFFE mTLS, `atenet-router` request parking, `atenet-egress` TLS secret swap | Translates declarative `Gateway` + `Model` credentials into per-actor `EgressPolicy` rules; reaches actors exclusively via `atenet-router` (`#700`); zero secrets in `spec.env` |
| **Inside the sandbox** | Boots PID 1 from `ActorTemplate` image with zero opinion on contents | Mounts `/opt/ax/ax-runner` (`#620`), hydrates Git/skills/MCP into `$AX_WORKSPACE` (`#723`), invokes `/usr/local/bin/ax-launcher` (`#734`) |
| **Multi-turn & agent semantics** | None—an actor is just an HTTP/gRPC endpoint on port 80 | Sessions, long-term memory, steering (`TaskService`), multi-task coordination, registries, models, and trajectories (`#724`) |

---

## 2. The Seven Pillars: From Task Orchestrator to Agentic Platform

AX starts as a crisp task orchestrator because a cheap, suspendable, strongly isolated `Task` is the hardest foundation to get right. Once `1 Task = 1 Actor` over inbound port 80 is settled, AX grows into an agentic platform along **seven concrete capabilities** listed in [`google/ax#724`](https://github.com/google/ax/issues/724) and [`docs/roadmap.md`](https://github.com/google/ax/blob/main/docs/roadmap.md):

| # | Platform Pillar (`#724`) | Why It Lives in AX (Not Substrate) | Upstream Anchors (`google/ax`) | Proven in `ax-experiments` |
|---|---|---|---|---|
| **1** | **Session management** | Substrate snapshots raw bytes on disk; it has no notion of conversation turns, session IDs, or transcript history across `suspend`/`resume`. AX models multi-turn conversations (`spec.sessionId`, `AX_SESSION_FILE`) so users and harnesses resume coherent threads across cold process restarts (`#683`). | `docs/roadmap.md §5`, `#621` (`AX_SESSION_FILE`), `#670` (Hero Demo Step 3 Turn 2) | [`genkit/`](../genkit/README.md) (persisted A2A `contextId` across `suspend`/`resume`), [`hero-demo/`](../hero-demo/README.md) Step 3 |
| **2** | **Memory** | Per-task `/workspace` snapshots and `Tag`s scope state to a single task lineage. Long-term **Memory** outlives any individual `Task`, giving agents scoped storage and retrieval shared across sessions and tasks without forcing every task to fork one monolithic filesystem. | `docs/roadmap.md §5` (*Sessions and Memory*) | Gap to prototype post-`#692`; complements per-task snapshots & OKF knowledge bundles (`okf/`) |
| **3** | **Multi-task coordination** | Real agentic work fans out into trees and swarms—planning, delegating, retrying, and comparing speculative branches (`docs/concepts.md`). AX layers cheap task branching (`ForkTask` over Substrate `Tag`s), parent-child lineage (`status.parentTask`), and inter-task communication protocols (`Agent` specs, A2A/MCP bridges) atop Substrate's `atenet-router`. | `#669`/`#670` (`ForkTask`), `#696` (stateless `Workspace`), `docs/roadmap.md §2–3` | [`swarm/01..08`](../swarm/README.md), [`genkit/01–02`](../genkit/README.md) (EGM panel & in-cluster MCP$\rightarrow$A2A delegation), [`dgem/03`](../dgem/README.md) (specialist router) |
| **4** | **Input steering** | Autonomous agents are rarely one-shot shell scripts: they pause for clarification, request tool approvals, or accept mid-run course corrections. Rather than polling a coarse status file from `ax-server` (`#690`/`#743`), AX keeps `TaskState` compute-aligned (`#731`) and layers caller/session-owned progress + structured inbound steering (`TaskService` `Send`/`List`/`Watch`, `#692`) over port 80—paired with future Substrate actor self-suspend (`substrate#450`) to reclaim idle sandboxes to 0 RAM and wake them transparently via `atenet-router`. | `#692` (`TaskService`), `#731` (`TaskState`), `#690`/`#738` (caller-owned completion), `docs/roadmap.md §3` | [`agy/02`](../agy/README.md) (cascading `dgem` `PreToolUse` gate + live `ax ssh` HITL), [`ax-central`](../okf/ax-central.md) inline HITL approval |
| **5** | **Registries** | Every organization needs governed catalogs of **MCP servers**, **skills** (`SKILL.md`), and **prebuilt runner/agent images** rather than ad-hoc URLs pasted into every prompt. AX resolves registries declaratively in `Workspace` and enforces policy/allowlists before code runs inside the sandbox. | `docs/concepts.md`, `docs/roadmap.md §1, §4, §7`, `#678` (release defaults) | [`genkit/workspace.yaml`](../genkit/workspace.yaml) (skills + MCP), [`ax-images`](../okf/ax-images.md) (`@sha256` multi-arch images), [`ax-central`](../okf/ax-central.md) Image Registry Catalog |
| **6** | **Models** | Binding LLM providers, model IDs, sampling parameters, and rotated API keys as first-class cluster resources (`Model` in `ax.io/v1alpha1`) decouples agent code from credentials and enables **multi-model tasks** (e.g., a fast System-1 policy/router model paired with a frontier System-2 reasoner) with keys injected strictly at `atenet-egress`. | `docs/concepts.md`, `docs/roadmap.md §1`, **`#709`** (`repeated models` on `TaskSpec`) | [`dgem/`](../dgem/README.md) & [`agy/`](../agy/README.md) (System-1 DiffusionGemma policy model + System-2 Gemini/Antigravity coding model) |
| **7** | **Trajectory collection** | Debugging, evaluating, and auditing agents requires structured **trajectories**—correlated prompts, model responses, tool invocations, process executions, and lifecycle state transitions—captured automatically at the `ax-runner` / `ax-server` layer via OpenTelemetry without custom instrumentation inside untrusted agent containers. | `docs/roadmap.md §4` (*Telemetry and Trajectory Collection*), `#665`/`#675` (`ax.task.state_changed`) | [`viz/`](../viz/README.md) (`SCHEMA.md`, `ax-trace`, Lit 3 replay UI, and [`FRICTION-REPORT.md`](../viz/FRICTION-REPORT.md) on `parent_task_id`, `correlation_id`, W3C `traceparent`) |

---

## 3. Why This Architecture Compounds Instead of Bloating

Every one of the seven pillars reinforces the same three invariants from [Document 2](./02-the-three-pivots.md):

1. **Zero new sandbox privilege:** Models inject keys at `atenet-egress`, registries resolve before/at setup, steering flows *inbound* over port 80, and trajectory collection happens at `ax-runner` / `ax-server`—none of the seven pillars requires giving untrusted agent code outbound access to `ax-server` or cluster secrets.
2. **Cold-start & scale-to-zero preserved:** Because Sessions live on `$AX_WORKSPACE`, Memory lives outside the sandbox, and `atenet-router` wakes actors on inbound `TaskService.Send`, a cluster (or laptop running `ate-local`) can keep thousands of idle conversations parked at **0 RAM**.
3. **Substrate stays small and reusable:** Keeping all seven agentic abstractions in AX lets Agent Substrate remain a focused, stable `v1.0` actor runtime usable by non-AX workloads as well.

---

## 4. How This Guide Expands on `google/ax#732`

Upstream [`google/ax#732`](https://github.com/google/ax/pull/732) distills the relationship into three README paragraphs (compute runtime vs. orthogonal agentic platform, plus portability across Google, customer clusters, and on-prem). The four documents in `concepts/` serve as the deeper architectural companion behind each statement:

1. **"Substrate is the compute runtime layer AX relies on"** $\rightarrow$ [Document 1](./01-substrate-and-ax-mental-model.md) explains why both layers have PostgreSQL outside `etcd` and how `WorkerPool`, `ActorTemplate`, `atenet-router`, and `atenet-egress` achieve `<100 ms` wakeup.
2. **"AX runs each task on Substrate, and everything else is orthogonal"** $\rightarrow$ [Document 2](./02-the-three-pivots.md) traces how AX narrowed that task-execution seam down to inbound port-80 push (`#688`), cold-start resume (`#683`), and stateless `Workspace` + `ForkTask` (`#696`/`#669`).
3. **"Runs the same way inside Google, on customer clusters, and on-prem" (and on a laptop)** $\rightarrow$ [Document 3](./03-datacenter-to-laptop.md) and [`ate-local/LOCAL-BACKEND.md`](../ate-local/LOCAL-BACKEND.md) examine the laptop end of that portability spectrum (`#689`, `#712`) and six empirical swarm learnings.
4. **"Grow into an agentic platform"** $\rightarrow$ §2 above maps all seven capabilities from `#724`/`#732` to `docs/roadmap.md`, active upstream issues, and runnable `ax-experiments` prototypes.
