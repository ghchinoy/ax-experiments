# Proposal: `ate-local` — Native macOS Local Substrate Control Plane backed by Apple Container

### Summary
`ate-local` is a lightweight, standalone daemon that implements the Agent Substrate Control gRPC interface (`ateapipb.ControlServer`), backed by the macOS native Apple `container` CLI runtime (`/usr/local/bin/container`).

It provides a zero-overhead local development environment for AX on macOS, enabling developers to create, resume, suspend, and execute agent harnesses in isolated microVM containers without requiring Kubernetes, `kind`, Redis, GCS, or Envoy.

---

### Capabilities & Features

1. **Substrate Control API Compatibility**:
   Implements the core `ateapipb.ControlServer` RPC surface used by `ax` and `internal/substrate/client.go`:
   - `CreateAtespace`, `GetAtespace`, `ListAtespaces`, `DeleteAtespace`
   - `CreateActorTemplate`, `GetActorTemplate`, `ListActorTemplates`, `DeleteActorTemplate`
   - `CreateActor`, `ResumeActor`, `SuspendActor`, `DeleteActor`, `ListActors`, `ListWorkers`

2. **Native MicroVM Isolation via Apple `container`**:
   Leverages Apple's native containerization on the macOS Virtualization framework. Each actor runs in an isolated, hardware-accelerated Linux environment (`arm64`).

3. **Direct Host-to-Container Routing (Zero Network Overhead)**:
   Apple container assigns each instance an IPv4 address directly on the macOS `vmnet` bridge (`192.168.64.0/24`). `ate-local` returns this IP in `WorkerAssignment.WorkerPodIp`, allowing `ax` and host tools to dial the actor's guest port directly without setting up complex Envoy `ext_proc` sidecars or ingress port forwarding.

4. **Configurable Templates & Resource Bounds**:
   Declaratively map `ActorTemplates` in `ate-local.yaml` to container images (`debian:12`, custom harness images), CPU allocation, memory limits, and volume mounts.

5. **Lifecycle Management**:
   - `CreateActor`: Registers actor metadata and binds template.
   - `ResumeActor`: Starts/creates container, extracts `vmnet` IP, waits for port readiness, sets state to `RUNNING`.
   - `SuspendActor`: Issues `container stop`, cleanly releasing Mac CPU and RAM.
   - `DeleteActor`: Issues `container delete --force`, tearing down resources.

---

### Why This Is Useful for Developers

1. **Zero-Cluster Inner Loop for Agent Developers**:
   Today, running AX with Substrate requires either a remote GKE cluster or a heavy local `kind` cluster with Redis, Valkey, GCS/S3, and `atenet` routing. `ate-local` reduces this to a single binary with zero dependencies beyond the macOS `container` CLI.
2. **Laptop & Battery Friendly on Apple Silicon**:
   Running `kind` or Docker Desktop on a Mac incurs constant background CPU and battery drain from heavy virtualization daemon layers. Apple `container` uses lightweight, on-demand microVMs that stop completely when suspended.
3. **100% Production-Aligned Interface**:
   Developers write code and configure tasks against the standard Substrate Control API. A task or harness validated locally with `ate-local` deploys without configuration changes to production GKE/Substrate clusters.

---

### Why Now?

1. **AX & Substrate Convergence**:
   AX has standardized its execution model around Agent Substrate actors. As the architecture stabilizes around `internal/substrate/` and `ateapipb`, the biggest missing piece for developer adoption is a lightweight, low-friction local onboarding story.
2. **Maturity of Native macOS Containerization**:
   macOS now features the first-class `container` CLI runtime built on the virtualization framework. Leveraging this native capability gives AX a best-in-class developer experience on Apple Silicon.
3. **Lowering the Contribution Barrier**:
   Providing an instant, 2-second local startup loop allows community developers to test harness changes, create new skills, and experiment with agent execution without cloud credentials or cluster setup scripts.

---

### What This Cannot Do (Limitations & Non-Goals)

To keep expectations clear, `ate-local` is explicitly scoped for local developer inner-loops and does **not** replace full production Substrate:

1. **No In-Memory Process Checkpoint/Restore (No RAM Snapshots)**:
   - Production Substrate achieves sub-second hibernation via gVisor (`runsc checkpoint`) or Cloud Hypervisor VM memory snapshots with `userfaultfd` demand-paging.
   - Apple `container` currently lacks a user-space memory checkpoint/restore primitive.
   - In `ate-local`, `SuspendActor` issues a clean container stop (`container stop`), and `ResumeActor` cold-starts or reboots the container. Volatile RAM state is not preserved across hibernation cycles (filesystem state on mounted volumes is preserved).
2. **Single-Host macOS Scope (No Distributed Scheduling)**:
   - `ate-local` runs solely on a single local macOS machine. It does not manage multi-node worker pools, node affinity, or cross-node migration.
3. **No Envoy Ingress Mesh or Identity-Aware Proxy (`atenet`)**:
   - Production uses Envoy with `ext_proc` to park incoming HTTP requests and trigger actor re-animation, with mTLS via SPIFFE/atunnel.
   - `ate-local` bypasses this entirely: it exposes the container's direct `vmnet` bridge IP (`192.168.64.x`), which is directly dialable by the host `ax` client. It does not support request parking or global DNS meshes (`*.actors.resources.substrate.ate.dev`).
4. **No External Storage Backends (No Redis or GCS/S3)**:
   - State is stored in-memory in the local daemon. Restarting `ate-local` resets active in-memory actor records (though existing containers on disk remain and can be managed).
5. **Not a Multi-Tenant Security Boundary**:
   - `ate-local` is designed for trusted local developer workloads, not for running untrusted third-party code with multi-tenant isolation guarantees.

---

### Proposed Next Steps & Roadmap

#### Phase 1: Community & Maintainer Feedback (Current)
- Open this proposal to gather maintainer feedback on whether `ate-local` belongs in `google/ax` (e.g., under `cmd/ate-local` or `internal/substrate/local`) or in `agent-substrate/substrate` as an official local development driver.
- Gather input on desired local CLI flags (e.g., `ax --local-substrate` or `ax-controller --substrate-endpoint=localhost:50051`).

#### Phase 2: Persistent Working Volume Emulation
- Add support for automatic host-directory binding (e.g., `~/.ax/volumes/<actor-id>/workspace`) mapped into `/workspace` inside the container.
- This ensures that while volatile RAM is cleared on suspend, all filesystem edits, git clones, and task outputs persist across `SuspendActor` and `ResumeActor` turns.

#### Phase 3: Exploring Checkpoint / Fast Resume Mechanisms
- Investigate whether container image export/commit or direct macOS Virtualization framework APIs can provide snapshotting for faster hydration.
- Benchmark cold-start vs. warm-container standby pools on Apple Silicon.

#### Phase 4: Upstream Pull Request
- Once maintainers validate the design and external PR intake is reopened, submit the clean, pre-tested branch (`feat/ate-local-apple-container`) adhering to Google Go Readability guidelines.

---

### Status & Proof of Concept

A complete, working implementation has been validated on macOS:
- **Branch**: `feat/ate-local-apple-container` (based cleanly on `google/ax:main` at `d8ed0fe`)
- **Code**: `cmd/ate-local/`, `internal/atelocal/`, `examples/ate_local/`, `docs/ate-local.md`
- **Verification**: Unit tests (`go test -v ./internal/atelocal/...`), live Apple container tests, and an end-to-end automated demo script (`./examples/ate_local/run_demo.sh`) all pass with 100% Google Go readability compliance.
