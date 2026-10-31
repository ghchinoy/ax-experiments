# Feature Proposal: Native macOS Local Development for AX via Apple Container & `ate-local`

> **Document Status**: Internal Proposal & Review Document  
> **Author**: Hussain Chinoy (`ghchinoy@google.com`)  
> **Target Audience**: AX and Agent Substrate committers, maintainers, and platform engineers  
> **Working Branch**: [`ghchinoy/ax:feat/ate-local-apple-container`](https://github.com/ghchinoy/ax/tree/feat/ate-local-apple-container) (cleanly rebased on `google/ax:main` at `f0228f1`)  
> **Companion Guides**: [`TESTING.md`](/ate-local/TESTING.md), [`/swarm/GUIDE.md`](/swarm/GUIDE.md), [`/viz/FRICTION-REPORT.md`](/viz/FRICTION-REPORT.md)  
> **Archived Drafts**: [`archive/prior-proposal.md`](/ate-local/archive/prior-proposal.md), [`archive/glidepath.md`](/ate-local/archive/glidepath.md)

---

## 1. Executive Summary

This proposal introduces **`ate-local`**, a lightweight, standalone daemon that implements the **Agent Substrate Control API** (`github.com/agent-substrate/substrate/pkg/proto/ateapipb.ControlServer`), backed by macOS's native **Apple `container`** CLI runtime (`/usr/local/bin/container`).

With `ate-local`, an AX developer on an Apple Silicon Mac can run the complete, unmodified AX control plane and execute isolated Tasks (including `ax apply`, `ax resume`, `ax describe`, `ax ssh`, and `ax delete`) in seconds—**with zero Kubernetes cluster, Docker Desktop, `kind`, host Redis installation, GCS buckets, or cloud credentials required**.

We have built, verified, and measured this capability on top of upstream AX `main` (`d0bc38b`). This document presents:
1. The developer experience (DX) case for native Apple container execution.
2. The architectural design and concept mapping onto the Substrate Control specification.
3. Rigorous, empirically measured performance benchmarks on Apple Silicon.
4. The "glidepath" enabling developers to prototype locally on macOS and deploy the exact same specifications to production Kubernetes with Agent Substrate without modification.
5. A proposed 3-part documentation and community guide series.
6. The core architectural question for maintainers: **where should this capability live (`google/ax` vs. `agent-substrate/substrate`)?**

---

## 2. Why Apple Container for Local Development? (The DX Case)

### The Current Friction: The "Day 0" Onboarding Barrier

Today, running AX against Agent Substrate requires physical compute pods managed by Kubernetes:
- **Option A (Remote GKE)**: Requires provisioning a GKE cluster with gVisor enabled, deploying Valkey, configuring GCS buckets and Workload Identity, setting up Envoy ingress (`atenet`), and authenticating `gcloud`. For local experimentation or skill authoring, this is slow, complex, and incurs cloud billing.
- **Option B (Local `kind` Cluster)**: Running Substrate on `kind` (Kubernetes-in-Docker) on a Mac requires allocating a persistent nested Linux VM (typically 4–8 GB RAM, multiple CPU cores) via Docker Desktop or Podman Machine. This results in:
  - Continuous background CPU and battery drain on Apple Silicon laptops even when no tasks are running.
  - Multi-hop networking (Host → Docker VM → KinD Node Pod → Worker Pod) requiring complex port-forwarding scripts.
  - High friction for community contributors who only want to author a Task, test a custom MCP tool, or debug `ax ssh`.

### The Adoption Funnel Reality

Consider the developer journey for someone discovering AX and Agent Substrate today:

```
[ Traditional Funnel: High Onboarding Friction ]
Discover AX/Substrate ──> Must provision GKE or configure local kind / Redis / GCS ──> High drop-off before first prompt

[ Glidepath Funnel: Instant Conversion ]
Discover AX/Substrate ──> Seconds to launch local stack with ate-local ──> Prototype locally ──> Deploy exact same spec to GKE!
```

1. **Lowering the Floor, Raising the Ceiling**:
   - `ate-local` lowers the floor: a developer needs only their MacBook, `/usr/local/bin/container`, and the `ax` CLI.
   - Agent Substrate raises the ceiling to cloud scale: high-density multi-tenant isolation, 30x+ hardware oversubscription, and sub-second process restoration in production.
2. **Zero Specification Throwaway**:
   - Because `ate-local` implements the exact `ateapipb.Control` API, **a task or harness tested locally requires zero code or configuration changes to deploy to production Kubernetes with Substrate** (differing only in container image target while multi-arch runner images are pending).
   - This follows the proven *"develop here, ship there"* model popularized by Docker Compose and Minikube.

### The Apple Container Advantage on macOS

Apple's native `container` CLI (shipped with the macOS Virtualization framework) offers distinct architectural advantages for developer inner loops:

| Feature | Docker Desktop / `kind` on Mac | Apple `container` (`/usr/local/bin/container`) | Developer Experience Impact |
|---|---|---|---|
| **Virtualization Model** | Persistent Linux VM running constantly in the background | Instant, on-demand microVMs using native macOS Hypervisor | No always-on Linux VM; helper processes idle at ~0.0% CPU when tasks are stopped. |
| **Networking & Reachability** | Multi-layer NAT/bridge inside Docker VM; requires port-forwarding tunnels | Direct IPv4 allocation on macOS `vmnet` bridge (`192.168.64.0/24`) | **Host processes dial container IPs directly.** AX controller, readiness probes, and `ax ssh` reach the guest with zero proxies. |
| **Startup Latency** | Minutes to boot `kind`, sync images, and deploy operators | Sub-second microVM creation and launch (~0.6s measured) | Rapid inner loop for task editing and verification. |
| **Prerequisites** | Heavy third-party virtualization software and licensing | First-party macOS CLI; zero additional host daemons needed | Low barrier to entry for any developer on Apple Silicon. |
| **Interface Parity** | Local cluster manifests differ from production | Exact same `ateapipb.Control` gRPC interface | Code and manifests tested locally deploy without modification to production. |

---

## 3. Why Now?

1. **AX & Substrate Convergence**:
   AX has standardized its execution model around Agent Substrate actors. As the architecture stabilizes around `internal/substrate/` and `ateapipb`, the biggest missing piece for developer adoption is a lightweight, low-friction local onboarding story.
2. **Upstream Architecture Simplification**:
   Upstream transitioned AX from Redis Streams and a separate `ax-controller` worker pool to direct, synchronous reconciliation inside `ax-server` (commit `ac23328`). This reduced the local control plane from four processes to three, with `ax-server` dialing Substrate directly. An `ate-local` backend slots into this streamlined architecture cleanly.
3. **Maturity of Native macOS Containerization**:
   macOS now features the first-class `container` CLI runtime (version 1.0) built on the virtualization framework. Leveraging this native capability gives AX a best-in-class developer experience on Apple Silicon.
4. **Lowering the Contribution Barrier**:
   Providing an instant local startup loop allows community developers to test harness changes, create new skills, and experiment with agent execution without cloud credentials or cluster setup scripts.

---

## 4. High-Level Architecture & Concept Mapping

### System Topology

AX is designed to be compute-decoupled: the server never interacts directly with low-level sandboxes or workers. Instead, it speaks gRPC exclusively to the Substrate Control API:

```
[ Local macOS Developer Inner Loop ]

   ax CLI (localhost:8090)
     │  gRPC (pkg/apis/v1alpha1.AX)
     ▼
   ax-server (:8090)
     ├── Valkey (:6379, runs in Apple container for resource store & distributed locks)
     │
     └── gRPC (ateapipb.ControlServer)
           │
           ▼
         ate-local (:50051)
           │  subprocess CLI (/usr/local/bin/container)
           ▼
         Apple Container (Debian 12 on vmnet: 192.168.64.x)
           ├── HTTP /readyz (:80)
           ├── guest.ProcessService for `ax ssh` (:80)
           └── ax-task-runner (linux/arm64)
```

> **Note on Redis / Valkey**: While `ate-local` itself has zero dependencies beyond the macOS `container` CLI, running the full AX stack currently requires a Redis-protocol store for task state and event streaming. In our local stack, Valkey runs inside an Apple container, avoiding any host package installation.

### Substrate Architectural Mapping

`ate-local` maps Substrate abstractions onto lightweight local primitives:

| Agent Substrate Concept | Production (Kubernetes + gVisor) | Local (`ate-local` + Apple Container) |
|---|---|---|
| **Control Plane** | `ate-api-server` backed by Redis & etcd | Standalone Go daemon (`ate-local`) with in-memory metadata store |
| **Worker Pool** | Pre-warmed Kubernetes Pods running `ateom-gvisor` | On-demand or pooled Apple containers |
| **Actor Creation** | Logical record in Redis (`ACTOR_STATE_SUSPENDED`) | In-memory record + template binding |
| **Actor Resume** | Restores snapshot into worker pod, returns Pod IP | Starts Apple container, inspects `vmnet` IP, returns `WorkerPodIp` |
| **Actor Suspend** | Process checkpoint to GCS snapshot | `container stop`, cleanly releasing host CPU and RAM |
| **Actor Deletion** | Reclaims worker and deletes snapshots | `container delete --force` |
| **Actor Ingress** | Envoy `ext_proc` router (`atenet`) + SPIFFE mTLS | Direct TCP/gRPC routing to container's `192.168.64.x` bridge IP |
| **Egress Policies** | Envoy network policy filters | In-memory policy storage (accepted for API completeness) |

---

## 5. What We Implemented

All code has been implemented, formatted to Google Go Readability standards, and pushed to branch [`feat/ate-local-apple-container`](https://github.com/ghchinoy/ax/tree/feat/ate-local-apple-container).

### Core Components

1. **`internal/atelocal` (Substrate Control Service & Container Runner)**:
   - **`server.go`**: Implements the full `ateapipb.ControlServer` interface:
     - `CreateAtespace`, `GetAtespace`, `ListAtespaces`, `DeleteAtespace`
     - `CreateActorTemplate`, `GetActorTemplate`, `ListActorTemplates`, `DeleteActorTemplate`
     - `CreateActor`, `ResumeActor`, `SuspendActor`, `PauseActor`, `GetActor`, `ListActors`, `DeleteActor`, `ListWorkers`
     - `CreateActorEgressPolicy`, `GetActorEgressPolicy`, `UpdateActorEgressPolicy`, `DeleteActorEgressPolicy`
   - **`runner.go`**: Mockable `ContainerRunner` interface abstracting the Apple `container` CLI:
     - Inspects JSON output to extract assigned IPv4 addresses from the `vmnet` bridge (`CleanIPv4`).
     - **`vminit` Fallback**: Automatically detects and uses local `ghcr.io/apple/containerization/vminit` image snapshots when default virtualization image pulling encounters cache issues.
     - **Volume Resolution**: Expands relative volume bind paths to absolute host paths.
     - **Name Sanitization & Hashing**: Ensures container names never exceed the Apple container runtime's length limits.
   - **`config.go`**: Declarative template configuration mapping actor templates to container images, resources, ports, and mounts.

2. **`cmd/ate-local` (Standalone Daemon)**:
   - Command-line entrypoint serving gRPC on `127.0.0.1:50051`.
   - Uses structured `log/slog` logging matching upstream AX.
   - Uses `signal.NotifyContext` for graceful shutdown, safely stopping active containers on `SIGINT`/`SIGTERM`.

3. **`examples/ate_local/local-stack.sh` (Local Orchestration Helper)**:
   - Manages the entire local AX stack: **Valkey → `ate-local` → `ax-controller` → `ax-server`**.
   - Subcommands: `up`, `down`, `status`, `logs`, `reset`.
   - **Strict Dependency Ordering**: Waits for each service's port to accept TCP connections before starting dependent components, completely eliminating gRPC reconnect backoff stalls.
   - **Pre-flight Port Conflict Detection**: Fails cleanly with descriptive errors if another host process holds port 6379, 50051, or 8090.
   - Cross-compiles a `linux/arm64` build of `ax-task-runner` and mounts it into task containers.
   - Emits `.ax-local/env` for simple `source .ax-local/env` CLI configuration.

4. **`examples/ate_local/task-local.yaml`**:
   - A verified, Apple-silicon-native Task specification running `debian:12` with `debug: true`.

5. **`Makefile` Integration**:
   - Targets added: `build-ate-local`, `run-ate-local`, `local-up`, `local-down`, `local-status`, `local-logs`, `local-reset`.

---

## 6. Verification & Measured Performance

All measurements were taken on **Apple Silicon (macOS 26.6.2)** running **Apple `container` 1.0.0** and **Go 1.27.1** against AX base **`d0bc38b`** across 3 consecutive runs (reported as range and median).

### Empirical Benchmark Data

| Operation | Measured Range | Median | Methodology & Verification |
|---|---|---|---|
| **Raw Container Start** | `0.55s – 0.68s` | **`0.63s`** | `container run --progress none --rm debian:12 true` (warm image cache) |
| **Local Stack Startup (`local-stack up`)** | `3.29s – 3.58s` | **`3.35s`** | Starts Valkey, builds/checks binaries, boots `ate-local`, `ax-controller`, `ax-server`, and verifies all 3 ports open |
| **`ax apply` Task Submission** | `0.03s – 0.30s` | **`0.15s`** | CLI RPC to `ax-server`, writes record to Valkey and publishes stream event |
| **`ax resume` CLI RPC** | `0.02s – 0.16s` | **`0.03s`** | CLI RPC to `ax-server` updating phase to `Running` |
| **Resume to Ready (`WorkerIp` + `Ready=True`)** | `0.59s – 0.92s` | **`0.70s`** | Real latency: `ax-controller` claims worker, spawns Apple container, polls `/readyz` on `:80` until HTTP 200, sets `WorkerPodIp` |
| **`ax ssh` Execution Round-Trip** | `0.03s – 0.12s` | **`0.03s`** | Real execution: dials `192.168.64.x:80` directly via `guest.Dial`, executes `uname -sm`, verified output `Linux aarch64` |
| **Full Inner Loop (apply → resume → ready → ssh)** | `0.68s – 1.28s` | **`1.13s`** | Complete developer loop from raw task definition to remote command output |
| **`ax delete` Teardown** | `0.53s – 3.54s` | **`0.57s`** | Controller issues `DeleteActor`, stops and deletes Apple container, removes record |
| **Live Reconciler & Exec Test** | `1.60s` | `1.60s` | Unit test: compiles arm64 task-runner, runs `TaskReconciler`, launches container, executes `uname -sm` |
| **Live Apple Container Test** | `2.92s` | `2.92s` | Unit test: full Control lifecycle (`CreateActor` → `ResumeActor` → IP inspect → `SuspendActor` → `DeleteActor`) |
| **Idle Host Overhead** | `0.00% – 0.70%` | **`0.07%`** | Sampled across all Apple container background processes over 10s window |

*(Note on previous drafts: Earlier draft notes referenced a 40ms "resume" figure; that measured only the asynchronous CLI RPC return before container boot. The 0.70s median above reflects the true end-to-end time for the Apple container to boot, acquire its IP, and pass `/readyz` validation).*

### Test Suite Results

- `go test -v ./internal/atelocal/...`: **5 passed**, 0 failed (mock lifecycle, template deduplication, egress policy, live container test, live reconciler test).
- `go test ./...`: **Passed** across all upstream packages.
- `addlicense -check .`: **Passed** with 100% Apache 2.0 license header compliance.
- Google Go Readability: Reviewed against `~/projects/agent-skills/plugins/go-readability` guidelines (canonical `Func(<inputs>) = <got>, want <want>` failures, `t.Context()`, and exported-first ordering).

---

## 7. The Developer Glidepath: From Local macOS to Production Substrate

One of the greatest challenges for high-density infrastructure like Agent Substrate is the onboarding gap. If evaluating Substrate requires deploying GKE, gVisor, Redis, and Envoy upfront, developer adoption faces friction.

`ate-local` creates an intuitive **3-stage developer glidepath**:

```
[ Day 0: Instant Local Sandbox ]
  Developer on MacBook + Apple container + ate-local
  - Sub-second container startup (0.63s)
  - Direct ax ssh debugging over vmnet (30ms latency)
  - Zero cloud costs, zero battery drain (0.07% idle CPU)
        │
        │ Commit exact same Task & Workspace YAML
        ▼
[ Day 1: CI / Staging ]
  GitHub Actions / Linux runners + KinD cluster
  - Automated smoke and regression testing
  - Multi-platform container image builds
        │
        │ Deploy exact same Task & Workspace YAML
        ▼
[ Day 2: Multi-Tenant Production ]
  GKE Cluster + Agent Substrate + gVisor
  - 30x+ hardware oversubscription via golden snapshots (as demonstrated by Substrate)
  - Sub-second process RAM teleportation across nodes (Substrate targets 100ms at p95)
  - Enterprise SPIFFE/mTLS identity & network policy enforcement
```

### Zero Specification Throwaway

Because `ate-local` speaks the official Substrate `Control` API, **no specifications, manifests, or client code are thrown away** when promoting an agent from a developer's laptop to production Kubernetes:
- The exact same `Task` schema is used locally and in production.
- Only `spec.image` differs today (local uses `debian:12` with our mounted arm64 runner; production uses the published `ax-task-runner` image). Once pending upstream PR [#400](https://github.com/google/ax/pull/400) merges multi-arch image builds, even the image field will be identical.

---

## 8. What This Cannot Do (Limitations & Non-Goals)

To ensure clear technical expectations:

1. **No Userspace Process Memory Snapshots (No RAM Checkpoints)**:
   - Production Substrate achieves fast hibernation via gVisor (`runsc checkpoint`) or Cloud Hypervisor VM memory snapshots with `userfaultfd` demand-paging.
   - Apple `container` currently lacks a user-space memory checkpoint/restore primitive.
   - In `ate-local`, `SuspendActor` stops the container (`container stop`), and `ResumeActor` cold-starts or reboots it. Volatile RAM state is not preserved across hibernation cycles (filesystem state on mounted volumes is preserved).
   - *Roadmap Alignment*: This directly matches Substrate's own roadmap item under Compute Priorities: *"Clean start from OCI for every activation"* and *"Disk-Only Resume Policy: Support for cost-optimized hibernation where only the filesystem state is preserved."*
2. **Single-Node macOS Scope**:
   - `ate-local` runs solely on a single local macOS machine. It does not manage multi-node worker pools, node affinity, or cross-node migration.
3. **No Envoy Ingress Mesh or Identity-Aware Proxy (`atenet`)**:
   - Bypasses Envoy and SPIFFE mTLS by exposing the container's direct `vmnet` bridge IP (`192.168.64.x`), which is directly dialable by the host `ax` client.
4. **Architecture & Multi-Arch Images**:
   - Apple `container` runs virtual machines matching the host architecture (`arm64`). Container images published exclusively for `amd64` require multi-arch compilation (as addressed in pending upstream PR [#400](https://github.com/google/ax/pull/400)).
   - *(Note: Apple `container` supports `--arch` and `--rosetta`, but Rosetta emulation has not been evaluated with the task runner).*
5. **In-Memory Control Plane State**:
   - `ate-local` maintains actor metadata in memory. Stopping the daemon resets active in-memory records (though containers on disk can be inspected or cleaned up).
6. **Not a Multi-Tenant Security Boundary**:
   - Designed for trusted local developer workloads, not for running untrusted third-party code with multi-tenant isolation guarantees.

---

## 9. Interaction with Upstream Status & Recent PRs

| Upstream PR / Issue | Status | Scope | Impact on `ate-local` / Local Development |
|---|---|---|---|
| [**#419**](https://github.com/google/ax/pull/419) (rakyll) | **Merged** (`ac23328`) | Moves reconciliation into `ax-server`; removes `ax-controller` and Redis Streams queue | **Highly positive.** Simplified the local stack from 4 processes to 3 (`ax-server` connects directly to `ate-local` via `--substrate-endpoint`). |
| [**#411**](https://github.com/google/ax/pull/411) / [#413](https://github.com/google/ax/pull/413) | **Merged** (`0126b72`, `92d297e`) | Fixes global flag parsing stopping at `--` in `ax ssh` and forwards stdin / Ctrl-C | Fully resolves the `-a` argument consumption bug reported in issue #410; interactive `ax ssh` works cleanly. |
| [**#421**](https://github.com/google/ax/issues/421) / [#463](https://github.com/google/ax/pull/463) | **Merged** (`397f7f2`) | Handles transient Substrate unavailability with retry backoff and Pending phase | Tasks no longer fail permanently during transient startup connection delays. |
| [**#400**](https://github.com/google/ax/pull/400) (rakyll) | Open | Multi-arch container image builds for `ax-task-runner` (`amd64` + `arm64`) | **Highly positive.** Once merged, upstream `examples/simple.yaml` will run natively on Apple container without needing a mounted local runner. |
| [**#405**](https://github.com/google/ax/pull/405) (mvanhorn) | **Merged** (`b2c59ae`) | Applies Task resource limits (`cpu`, `memory`) to `ActorTemplate` | **Implemented in `ate-local`:** parsed into `--cpus` and `--memory`. |
| [**#496**](https://github.com/google/ax/pull/496) (jbd) | **Merged** (`6a1d6ea`) | Binds at most one workspace per task (`workspace:` singular) | **Updated in Swarms & examples:** all manifests use singular `workspace:`. |
| [**#515**](https://github.com/google/ax/pull/515) (rakyll) | **Merged** (`2bfbcb8`) | Moves store to PostgreSQL; reads live actor state from Substrate (`GetActor`/`ListActors`) | **Verified end-to-end.** `local-stack.sh` now runs `postgres:17-alpine`, and `ate-local`'s `GetActor`/`ListActors` serve live actor state to `ax-server`. |
| [**#517**](https://github.com/google/ax/pull/517) (siyuanfoundation) | **Merged** (`353f650`) | Bumps Substrate to `v0.6.0` (`go.ate.dev/substrate`, `ResourceRequirements`) | **Updated in `ate-local`:** imports `go.ate.dev/substrate` and parses `CpuMillicores` / `MemoryBytes`. |
| [**#532**](https://github.com/google/ax/pull/532) (yongruilin) | **Merged** (`37dda66`) | Removes the `Reconciler` interface; `server.NewServer` requires a `*controller.TaskReconciler` with a `*substrate.Client` | **Validates `ate-local`'s design.** Because `ax-server` now exclusively speaks `ateapipb.ControlServer`, `ate-local` is the exact local control plane needed to run AX without Kubernetes. |
| [**#526**](https://github.com/google/ax/issues/526) (rakyll) | **Open (Issue)** | Local development commands (`ax local start`, `ax local status`, `ax local stop`) | **Direct alignment.** `ate-local` + `local-stack.sh` already implements the exact `up / status / down` lifecycle on macOS in 3s using native Apple `container` microVMs instead of a heavy Kind cluster. |

---

## 10. Proposed Documentation & Community Content Series

To support community growth and developer onboarding, we propose authoring a dedicated 3-part developer content series:

### Part 1: *"Zero to Sandboxed Agent in Seconds on macOS"*
- **Target Audience**: Developers new to AX or agent sandboxing.
- **Core Message**: AI agents need sandboxing, but your local laptop shouldn't need a heavy Kubernetes cluster just to test a prompt.
- **Content**:
  - Why untrusted agent code needs containerization.
  - Starting `ate-local` backed by native Apple `container` on Apple Silicon.
  - Running your first prompt turn in an isolated microVM with direct `vmnet` IP routing.

### Part 2: *"Authoring Skills & Managing Working Volumes Locally"*
- **Target Audience**: Agent builders creating custom tools and multi-turn workflows.
- **Core Message**: How to give agents persistent disk memory while keeping the runtime stateless and reproducible.
- **Content**:
  - Mapping persistent working directories (`/workspace`) across `SuspendActor` and `ResumeActor` turns.
  - Attaching local files, git repositories, and dependencies.
  - Inspecting and debugging active containers using native macOS tools (`container inspect`, `container exec`).

### Part 3: *"The Glidepath: Deploying Your Local Agent to Production on GKE with Agent Substrate"*
- **Target Audience**: Platform engineers and developers ready to scale to multi-tenant production.
- **Core Message**: The exact YAML and container images built on a Mac promote seamlessly to high-density Kubernetes infrastructure.
- **Content**:
  - Comparing `ate-local` (process lifecycle) vs. production Substrate (gVisor RAM snapshots).
  - Deploying AX and Substrate on GKE via `make deploy`.
  - Applying the exact same `Task` specifications to production.
  - How Substrate's 30x+ hardware multiplexing optimizes compute costs for idle agents in production.

---

## 11. Proposed Next Steps & Roadmap

### Phase 1: Direct Alignment with Issue #526 (`ax local start / status / stop`) *(Current)*

With PR [#515](https://github.com/google/ax/pull/515) making Agent Substrate the live source of truth for actor state, PR [#532](https://github.com/google/ax/pull/532) removing the `Reconciler` interface so `ax-server` always speaks `ateapipb.ControlServer`, and PR #504 closing in favor of Issue [#526 (`Local development`)](https://github.com/google/ax/issues/526):

1. **`ate-local` is now the only non-Kubernetes way to run `ax-server` locally:**
   - Because `server.NewServer` requires a `*controller.TaskReconciler` backed by a `*substrate.Client`, any local runtime must speak `ateapipb.ControlServer`.
   - While Issue #526 proposes `ax local start / status / stop` using a Kind cluster (`kind` + Docker/Podman + gVisor + Envoy + cert-manager + Postgres), `ate-local` + `local-stack.sh` provides the exact same `up / status / down` developer experience on macOS in ~3 seconds using native Apple `container` microVMs.
   - Furthermore, #532 introduced `internal/substrate/substratetest` (an in-memory `ateapipb.ControlServer` for unit tests); `ate-local` is its live-container counterpart.

---

## 12. Discussion Questions for Colleagues & Maintainers

### Question 1: Architectural Path & Issue #526 (`ax local`)
Given Issue #526 (`ax local start / status / stop`):
- **Option A (`ax local --runtime=apple-container` in `google/ax`)**: Should `ax local start` on macOS support an Apple `container` mode powered by `ate-local` (avoiding the heavy Kind + gVisor + Envoy setup when developing on Apple Silicon)?
- **Option B (`agent-substrate/substrate`)**: Should `ate-local` live in `agent-substrate/substrate` (`go.ate.dev/substrate`) as an official macOS local control plane for emulating Substrate?
- **Option C (Companion / Standalone Repository)**: Maintained as a dedicated open-source bridge tool (`ate-local` or `ax-local`).

### Question 2: In-Process `ax dev` Mode
Currently, `ax-server` requires Valkey/Redis for locking and task storage. Would maintainers welcome an in-process local development command (e.g., `ax dev` or `ax-server --dev`) that runs `ax-server` against AX's existing in-memory store (`internal/store/memory`) and in-memory locker? This would reduce the local macOS prerequisites strictly to the `ax` binary and Apple `container`.

### Question 3: Workspace Directory Binding
Should `ate-local` automatically provision a local host bind mount (e.g., `~/.ax/volumes/<actor-id>/workspace` mapped into `/workspace`) so that file edits and git checkouts persist across `SuspendActor` and `ResumeActor` turns without manual volume configuration?

---

## 13. Quick Links & Reproduction

- **Full Fork Branch Diff**: [`google/ax:main...ghchinoy:ax:feat/ate-local-apple-container`](https://github.com/google/ax/compare/main...ghchinoy:ax:feat/ate-local-apple-container)
- **Local Testing Guide**: [`TESTING.md`](/ate-local/TESTING.md)
- **Quick Test Commands**:
  ```bash
  git clone https://github.com/ghchinoy/ax.git && cd ax
  git checkout feat/ate-local-apple-container
  make local-up
  source .ax-local/env
  ax apply -f examples/ate_local/task-local.yaml
  ax resume local-task
  ax describe task local-task
  ax ssh local-task -- uname -sm
  make local-down
  ```
