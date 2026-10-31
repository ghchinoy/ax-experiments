# Developer Guide: An Intro to AX on Apple Container

> **Internal Review Document**  
> **Target Audience**: Developers, committers, and colleagues exploring AX prior to Kubernetes / Agent Substrate  
> **Prerequisites**: Apple Silicon Mac, Apple `container` CLI 1.0+, Go 1.26+  
> **Companion Files**: [`TESTING-ate-local.md`](./TESTING-ate-local.md), [`PROPOSAL-apple-container-substrate.md`](./PROPOSAL-apple-container-substrate.md), [`FRICTION-REPORT-correlation-and-swarm-telemetry.md`](./FRICTION-REPORT-correlation-and-swarm-telemetry.md), [`swarm/`](../swarm/), [`viz/`](../viz/)  

---

## 1. What is AX? (The 2-Minute Overview)

**AX (Agent Executor)** is a distributed runtime for autonomous agent workloads. Rather than treating an AI agent as a single, long-running process that runs to completion, AX models execution as a collection of small, declarative primitives:

- **`Task`**: The fundamental unit of isolated execution. A task defines an OCI container image, command, environment variables, compute limits, and bound workspaces. Tasks are cheap to create, isolate, suspend, resume, and throw away.
- **`Workspace`**: Declarative environment preparation. A workspace defines Git repositories to clone, inlined files to materialize, and MCP tools or skills to attach before the task command starts.
- **`Model`**: Declarative model provider configurations (e.g., `gemini-3.8-flash`) and credential bindings.

As AX's architecture guide states:
> *"An agent is not one process that runs to completion; over its lifetime it plans, delegates, retries, and fans work out. AX gives you one primitive that is cheap to create, isolate, suspend, and throw away, and lets the agent compose as many of them as its work demands."*

In production, AX runs these tasks as actors on **Agent Substrate** inside a Kubernetes cluster with gVisor. However, on macOS, running a full Kubernetes cluster (`kind`), Redis, GCS, and Envoy introduces significant friction.

**`ate-local`** bridges this gap: it implements Substrate's exact Control API backed by the native macOS **Apple `container`** runtime. You get real microVM isolation, real direct-dialable bridge IPs (`192.168.64.x`), and real `ax ssh` debugging on your laptop—with zero cloud infrastructure.

---

## 2. What Can You Do Right Now on a Mac?

With the `feat/ate-local-apple-container` branch and `ate-local`, here is what is fully functional today:

| Capability | Status | How It Works |
|---|:---:|---|
| **Declarative Task Lifecycle** | **Working** | `ax apply`, `ax resume`, `ax describe`, `ax delete` against Apple containers. |
| **Interactive Guest Debugging (`ax ssh`)** | **Working** | Dials the container's interior IP on port 80 via `guest.Dial` to execute commands or inspect state. |
| **Direct Host-to-Container Routing** | **Working** | Apple container assigns each microVM an IPv4 address on macOS `vmnet` (`192.168.64.0/24`), directly dialable without port-forwarding. |
| **Workspace Git Clones & Inlined Files** | **Working** | `ax-task-runner` clones git repositories and materializes declared files into `/workspace` on boot. |
| **Multi-Agent Swarm Fan-Out** | **Working** | Host orchestrates multiple parallel task containers concurrently on Apple Silicon. |
| **AI Agent Swarms (Gemini)** | **Working** | Sandboxed Python agents calling `gemini-3.8-flash` with credentials inherited from your environment. |
| **Filesystem Persistence** | **Working** | Volumes mounted at `/workspace` retain files across `ax suspend` and `ax resume` cycles. |

---

## 3. Quick Setup

### Step 1: Start the Local Stack
In your `ax` repository checkout (`feat/ate-local-apple-container` branch):

```bash
make local-up
source .ax-local/env
```

This starts `postgres:17-alpine` in an Apple container, `ate-local` on port 50051, and `ax-server` on port 8090 in dependency order (reconciliation runs directly in `ax-server`).

### Step 2: Build the Local Swarm Agent Image
For AI agent recipes, build our local arm64 agent image (bundles Python 3.10, git, ca-certificates, and the `google-genai` SDK):

```bash
container build -t ax-agent-local:latest -f ~/projects/ax-experiments/swarm/agent-image/Containerfile ~/projects/ax-experiments/swarm/agent-image
```
*(Takes ~10 seconds on Apple Silicon).*

### Step 3: Export Your Gemini API Key
```bash
export GEMINI_API_KEY="AIzaSy..."
```

---

## 4. Three Swarm Architectural Patterns

When thinking about "agent swarms" in AX prior to full Kubernetes/Substrate deployment, there are three distinct patterns:

```
[ Pattern 1: Host-Driven Fan-Out ]         [ Pattern 2: Multi-Agent Sandboxes ]         [ Pattern 3: Recursive Task Trees ]
      (Available Today)                          (Available Today)                              (Roadmap)

        Mac Host Script                            Mac Host Script                              Root Task Container
         │         │                                │         │                                    │         │
   ┌─────┴─────┐ ┌──┴────────┐                ┌─────┴─────┐ ┌──┴────────┐                    ┌─────┴─────┐ ┌──┴────────┐
   ▼           ▼ ▼           ▼                ▼           ▼ ▼           ▼                    ▼           ▼ ▼           ▼
Task 1      Task 2 ...    Task N           Agent 1     Agent 2 ...   Agent N              Subtask 1   Subtask 2 ... Subtask N
(Isolated microVM containers)              (Specialized AI personas calling Gemini)       (Spawned via in-container AX API)
```

1. **Pattern 1: Host-Driven Fan-Out (Available Today)**  
   A script on your Mac acts as the coordinator. It generates Task manifests, submits them via `ax apply`, resumes them in parallel, and collects results via `ax ssh`. The Mac host coordinates; AX provides isolated Linux microVM workers.
2. **Pattern 2: Multi-Agent Sandboxes (Available Today)**  
   Each Task container hosts an autonomous AI agent with a specific role, system instructions, and toolset. The host orchestrates multi-turn communication (e.g. streaming the proposer's output into the critic's sandbox).
3. **Pattern 3: Recursive Task Trees (Roadmap / Future)**  
   A root task container dials `ax-server` directly to dynamically spawn, monitor, and terminate its own child tasks. *(Locally, this requires routing to `ax-server` from inside the `vmnet` bridge and bundling the `ax` CLI into the guest image).*

---

## 5. Hands-On Swarm Recipes

The [`~/projects/ax-experiments/swarm/`](../swarm/) directory contains 8 executable recipes. All timings below were empirically measured on this Mac.

### Recipe 01: Hello Swarm (8 Parallel MicroVMs)
* **Goal**: Spin up 8 isolated tasks simultaneously. Each microVM reports its dynamic `vmnet` IP, internal hostname, and kernel architecture.
* **API Key Needed**: No.
* **Execution**:
  ```bash
  ~/projects/ax-experiments/swarm/01-hello-swarm.sh
  ```
* **Real Output (9 seconds total)**:
  ```text
  ==> [01 Hello Swarm] Spawning 8 parallel tasks on Apple Container...
  --> Applying and resuming 8 tasks...
  --> Waiting for all 8 microVMs to report Ready on vmnet...

  TASK NAME          WORKER IP        HOSTNAME                 OS / ARCH
  ---------          ---------        --------                 ---------
  hello-node-0       192.168.64.81    ate-default-hello-node-0 Linux aarch64
  hello-node-1       192.168.64.80    ate-default-hello-node-1 Linux aarch64
  hello-node-2       192.168.64.79    ate-default-hello-node-2 Linux aarch64
  hello-node-3       192.168.64.74    ate-default-hello-node-3 Linux aarch64
  hello-node-4       192.168.64.77    ate-default-hello-node-4 Linux aarch64
  hello-node-5       192.168.64.76    ate-default-hello-node-5 Linux aarch64
  hello-node-6       192.168.64.78    ate-default-hello-node-6 Linux aarch64
  hello-node-7       192.168.64.75    ate-default-hello-node-7 Linux aarch64

  ==> Swarm completed in 9s (provisioned and ready in 8s).
  ```

---

### Recipe 02: Parallel Repository Inspector
* **Goal**: Demonstrates AX Workspaces. Proves that `ax-task-runner` automatically clones git repositories and materializes inlined files into `/workspace` across parallel tasks.
* **API Key Needed**: No.
* **Execution**:
  ```bash
  ~/projects/ax-experiments/swarm/02-repo-inspector.sh
  ```
* **Real Output (13 seconds total)**:
  ```text
  ==> [02 Parallel Repo Inspector] Inspecting 3 git codebases across isolated Apple containers...
  --> Applying and resuming 3 inspection tasks...
  --> Waiting for tasks to report Ready...

  --- Results from isolated workspaces ---
  [repo-ax]:
  drwxr-xr-x 3 root root 4096 Sep 26 18:25 ax

  [repo-substrate]:
  -rw-r--r-- 1 root root   45 Sep 26 18:25 data.txt
  ```

---

### Recipe 03: Stochastic Fuzz / Seed Matrix
* **Goal**: Run 6 parallel tasks with varying random seeds to identify boundary failures or edge cases across isolated environments.
* **API Key Needed**: No.
* **Execution**:
  ```bash
  ~/projects/ax-experiments/swarm/03-seed-matrix.sh
  ```
* **Real Output (6 seconds total)**:
  ```text
  ==> [03 Seed Matrix] Running 6 parallel stochastic runs on Apple Container...
  --> Applying and resuming 6 matrix tasks...
  --> Waiting for all 6 matrix tasks to be Ready...

  TASK               SEED       OUTCOME      SIMULATION RESULT
  ----               ----       -------      -----------------
  matrix-seed-101    101        PASS         val=1933386042
  matrix-seed-202    202        PASS         val=1719276091
  matrix-seed-303    303        FAIL         edge case detected: remainder 0
  matrix-seed-404    404        PASS         val=1291056189
  matrix-seed-505    505        PASS         val=1076946238
  matrix-seed-606    606        PASS         val=862836287

  ==> Matrix run completed in 6s.
  ```

---

### Recipe 04: Specialized AI Code Review Panel
* **Goal**: 3 specialized AI agents in separate microVM containers review a Go database query from distinct angles: **Security Auditor**, **Go Readability Mentor**, and **Performance Engineer**.
* **API Key Needed**: **Yes** (`gemini-3.8-flash`).
* **Execution**:
  ```bash
  ~/projects/ax-experiments/swarm/04-review-panel.sh
  ```
* **Real Output (26 seconds total)**:
  ```text
  ============================================================
  Agent: panel-security-reviewer
  ============================================================
  * Critical SQL Injection Vulnerability: The id parameter is directly concatenated
    into the SQL string ("SELECT * FROM users WHERE id = " + id). Use parameterized queries.
  * Sensitive Data Exposure Risk (SELECT *): Retrieves all columns rather than explicitly
    projecting required fields, risking memory exposure of password hashes or tokens.

  ============================================================
  Agent: panel-readability-reviewer
  ============================================================
  * Error String Style & Wrapping: Error strings must not be capitalized or end with punctuation.
    Replace fmt.Errorf("Database query failed.") with fmt.Errorf("querying users: %w", err).
  * Unhandled Iteration Errors: Never discard errors with _ = rows.Scan(...); handle scan failure
    and always check rows.Err() after rows.Next().

  ============================================================
  Agent: panel-performance-reviewer
  ============================================================
  * Heap Allocations & Query Inefficiency: String concatenation forces heap allocations per execution;
    SELECT * fetches unneeded columns over the network.
  * Connection Lifecycle & Overhead: db.Query with rows.Next() allocates heavy sql.Rows.
    Replace with db.QueryRow(query, id).Scan(...) to immediately release connection to pool.
  ```

---

### Recipe 05: Multi-Agent Adversarial Debate
* **Goal**: Two AI agents engage in structured red-teaming. Agent 1 (Radical Performance Advocate) proposes running all database transactions purely in RAM. The host orchestrator captures this and streams it into Agent 2's container (Pragmatic SRE) for rebuttal.
* **API Key Needed**: **Yes** (`gemini-3.8-flash`).
* **Execution**:
  ```bash
  ~/projects/ax-experiments/swarm/05-debate.sh
  ```
* **Real Output (11 seconds total)**:
  ```text
  --- Round 1: Proposer's Opening Argument ---
  Disk I/O is a catastrophic architectural bottleneck that introduces latency penalties orders of
  magnitude slower than nanosecond-scale RAM access. Executing transactions purely in-memory eradicates
  all I/O wait states and serialization overhead, unlocking maximum theoretical hardware throughput.

  --- Round 2: Critic's Rebuttal (streamed into Critic container) ---
  Eliminating persistent writes completely sacrifices transactional durability, meaning an unexpected
  power loss will instantly vaporize your entire working state. Furthermore, operating without non-volatile
  storage renders robust disaster recovery impossible, turning routine node crashes into catastrophic data loss.

  ==> Multi-agent debate completed in 11s.
  ```

---

### Recipe 06: Map-Reduce Synthesis Swarm
* **Goal**: Scatter-gather swarm. 3 Mapper agents analyze different concepts (Kernel architecture, Distributed event streams, Bridge networking) in parallel. 1 Reducer agent synthesizes the 3 findings into an executive summary.
* **API Key Needed**: **Yes** (`gemini-3.8-flash`).
* **Execution**:
  ```bash
  ~/projects/ax-experiments/swarm/06-map-reduce.sh
  ```
* **Real Output (20 seconds total)**:
  ```text
  --> Executing 3 Mappers in parallel...
     [Mapper 1]: MicroVMs provide hardware-enforced isolation boundaries via dedicated guest kernels,
                 eliminating the shared-kernel attack surface inherent to standard Linux containers.
     [Mapper 2]: Distributed event streams decouple workers by acting as persistent, asynchronous intermediaries
                 that eliminate temporal, spatial, and throughput dependencies between producers and consumers.
     [Mapper 3]: Direct bridge routing minimizes latency by processing packets natively at the kernel network layer,
                 eliminating duplicate TCP/IP stack traversals and userspace context switches introduced by proxy sidecars.

  ============================================================
  SYNTHESIZED REDUCE RESULT
  ============================================================
  Modern infrastructure maximizes security, scalability, and throughput by eliminating shared bottlenecks
  across compute, messaging, and networking. Deploying MicroVMs establishes hardware-enforced kernel isolation
  to neutralize container attack surfaces, while distributed event streams asynchronously decouple worker execution.
  Complementing this foundation with direct bridge routing bypasses proxy sidecars at the kernel level,
  yielding a hardened, loosely coupled architecture engineered for ultra-low-latency execution.

  ==> Map-Reduce swarm completed in 20s.
  ```

---

### Recipe 07: Suspend & Resume Lifecycle Boundaries
* **Goal**: Demonstrates the real lifecycle boundaries of Apple container. Proves that files written to `/workspace` survive across `ax suspend` and `ax resume`, while the guest kernel and process tree are cleanly rebooted.
* **API Key Needed**: No.
* **Execution**:
  ```bash
  ~/projects/ax-experiments/swarm/07-suspend-resume.sh
  ```
* **Real Output (5 seconds total)**:
  ```text
  --> Step 1: Create and resume task...
  --> Step 2: Write state and check initial boot timestamp inside container...
  Wrote /workspace/data/checkpoint.txt. Initial kernel uptime: 1.00s
  --> Step 3: Suspending task (stopping Apple container to free host CPU/RAM)...
     Container state after suspend: stopped
  --> Step 4: Resuming task (cold-booting container with persistent volume)...
  --> Step 5: Verifying filesystem persistence vs process reset...
  SUCCESS: /workspace/data/checkpoint.txt persisted! Content: checkpoint-turn-1-data-payload
  Boot 1 uptime was: 1.00s | Boot 2 uptime is: 0.32s (rebooted into fresh VM)

  ==> Lifecycle verification completed in 5s.
  ```

---

### Recipe 08: Declarative `Task.spec.config` & Loopback Metadata
* **Goal**: Exercises structured `Task.spec.config` (`google.protobuf.Struct`, `#523`), single-Workspace file materialization (`#496`), and the loopback-only metadata boundary (`127.0.0.1:8099`, `#479`). Verifies that `/metadata/v1alpha1/ax/task` is readable inside the microVM over loopback while external requests to port 80 on the `vmnet` bridge IP return `404`.
* **API Key Needed**: No.
* **Execution**:
  ```bash
  ~/projects/ax-experiments/swarm/08-spec-config-metadata.sh
  ```

---

### Interactive Replay: The AX Swarm Visualizer
Recorded execution traces from these recipes can be replayed in real time using the interactive visualizer in [`viz/`](../viz/):

```bash
cd ~/projects/ax-experiments/viz/web
pnpm build && pnpm preview
```

Open the preview URL in your browser to inspect actor topology, microVM boot/readiness transitions, and direct inter-agent messaging with dual Force-Graph and Cytoscape rendering.

---

## 6. Developer Tips for Running Swarms on a Mac

1. **Laptop Sizing & Density**:
   - `ate-local` currently uses the default template resource bounds (2 vCPUs, 1024 MB RAM per container).
   - On a 10-core / 32 GB Apple Silicon machine, running swarms of **8 to 16 parallel microVMs** operates comfortably with ~0.07% idle CPU overhead when stopped.
   - For swarms exceeding 20 concurrent containers, adjust memory limits in `examples/ate_local/ate-local.yaml`.
2. **Inspecting Live Swarms with Native macOS Tools**:
   - List active swarm containers: `container list`
   - Inspect assigned `vmnet` bridge IPs: `container inspect ate-default-<task-name>`
   - Direct ping test: `ping 192.168.64.x`
3. **Clean Reset**:
   If a swarm run leaves tasks in an inconsistent state or you want to wipe local history:
   ```bash
   make local-reset
   ```

---

## 7. Security Realities for Local Development

- **API Key Visibility in `ps`**:  
  `ate-local` passes task environment variables to `container run` using `-e KEY=VALUE` arguments. On a local macOS machine, `ps aux` will show `GEMINI_API_KEY` while the `container run` command is executing. This is acceptable for single-user local development, but in production, Substrate injects credentials via mTLS sidecars or secret mounts.
- **Kubernetes Secret Fallback**:  
  The AX reconciler first attempts to resolve secrets using `kubectl get secret`. On a Mac with no Kubernetes cluster running, this lookup times out after 2 seconds and safely falls back to `os.Getenv("GEMINI_API_KEY")`.

---

## 8. What Is Not Here Yet (Honest Boundaries)

- **In-Memory Process Snapshots**: Apple container lacks a userspace checkpoint/restore primitive; suspend stops the microVM and resume boots fresh (disk persists, RAM resets).
- **In-Sandbox Recursive Spawning**: Tasks cannot yet spawn subtasks directly from inside the container without bridging port 8090 into the `vmnet` interface.
- **MCP Tool Registries**: Currently designed for in-cluster service endpoints.

---

## 9. Where This Leads: The Production Path

The beauty of experimenting with swarms on Apple container is that **the task specifications do not change when moving to production**:

```yaml
apiVersion: ax.io/v1alpha1
kind: Task
metadata:
  name: security-review-agent
  atespace: production
spec:
  image: "gcr.io/my-org/agent:latest" # switches to cloud registry
  workspace:
    name: app-code
```

When deployed to a production GKE cluster with Agent Substrate:
- The exact same Task manifest is submitted via `ax apply`.
- Substrate replaces cold-boot containers with **30x+ hardware oversubscription** and sub-second process RAM teleportation.
- Egress policies and enterprise SPIFFE identities are enforced automatically.

You develop and debug your swarms locally on your MacBook in seconds—and deploy them to planetary-scale infrastructure with zero rewrite.
