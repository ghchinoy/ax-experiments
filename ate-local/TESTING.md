# Testing `ate-local`: AX on Apple Container

> **Internal proposal first.** This is an exploratory prototype for review with
> colleagues across AX and Agent Substrate. A primary question we want your input
> on is **project placement**: should this capability live in `google/ax`
> (for example as `cmd/ate-local` or under `internal/substrate`), inside
> `agent-substrate/substrate` as an official local macOS control-plane provider,
> or as a standalone development tool?
>
> Please do not share or link to this document or the fork outside the team yet.

- Fork: https://github.com/ghchinoy/ax
- Branch: `feat/ate-local-apple-container` (rebased on `google/ax` `main` at `f0228f1`)
- Status: experimental prototype
- Companion Guides: [Proposal (`PROPOSAL.md`)](/ate-local/PROPOSAL.md), [Developer Intro & Swarm Recipes (`/swarm/GUIDE.md`)](/swarm/GUIDE.md), [Friction Report on Correlation & Telemetry (`/viz/FRICTION-REPORT.md`)](/viz/FRICTION-REPORT.md)

---

## What you are testing

AX normally runs Tasks as Agent Substrate actors on a Kubernetes cluster.
`ate-local` is a lightweight Go daemon that implements the exact same
Substrate Control gRPC API (`ateapipb.ControlServer`), but provisions and
manages each actor as a native macOS **Apple `container`** on the local `vmnet`
bridge (`192.168.64.x`).

This allows the upstream `ax` stack to run Tasks on your Mac
without Kubernetes, `kind`, gVisor, GCS, or cloud infrastructure:

```
ax CLI ──gRPC──> ax-server ──Control gRPC──> ate-local ──> Apple container
                    │
                    └──> Valkey (resource store, locks, pubsub)
```

| Component | Role | Default Port |
|---|---|---|
| `ax-server` | Direct-execution AX API server; manages locks, reconciles with Substrate | 8090 |
| Valkey | Redis-compatible resource store and lock coordinator (runs in Apple container) | 6379 |
| `ate-local` | Implements Substrate Control API using Apple `container` | 50051 |

Upstream transitioned AX from asynchronous Redis Streams worker pools (`ax-controller`)
to direct, synchronous reconciliation inside `ax-server` guarded by fine-grained distributed
locks. The local stack runs three components: Valkey, `ate-local`, and `ax-server`.

---

## Prerequisites

1. **Apple Silicon Mac** running macOS 26 or later.
2. **Apple `container` CLI** version 1.0 or later installed (`/usr/local/bin/container`).
   Verify with `container --version` and ensure `container list` responds.
   (If it does not respond, run `container system start`).
3. **Go toolchain** (Go 1.26+; matches `go.mod`).
4. **`git` and `nc`** (standard macOS preinstalls).
5. Ensure ports **6379**, **50051**, and **8090** are free. (The startup helper automatically checks and warns if another process holds them).

*No Kubernetes, Docker Desktop, `kind`, or cloud accounts are needed.*

---

## Get the code

```bash
git clone https://github.com/ghchinoy/ax.git
cd ax
git checkout feat/ate-local-apple-container
```

---

## 1. Automated tests (~8 seconds)

Run the focused test suite from the repository root:

```bash
go test -v ./internal/atelocal/...
```

| Test | What it exercises | Requires Apple container |
|---|---|---|
| `TestControlServer_AtespaceLifecycle` | Atespace create, get, list, and delete state machines | No (mock) |
| `TestControlServer_ActorLifecycle` | Actor create, duplicate rejection, mock resume, suspend, delete | No (mock) |
| `TestCleanIPv4` | CIDR stripping and IP normalization | No |
| `TestControlServer_TemplateDeduplicationAndEgressPolicy` | Template deduplication and full egress-policy CRUD | No (mock) |
| `TestControlServer_ReconcilerIntegration` | Real AX `controller.TaskReconciler` against `ate-local` | No (mock) |
| `TestControlServer_LiveAppleContainer` | Provisions, inspects IP, suspends, and removes real Apple container | **Yes** (live) |
| `TestControlServer_LiveReconcilerAndGuestExec` | Full end-to-end: compiles arm64 `ax-task-runner`, reconciles real `Task`, launches container, dials guest on `:80`, and executes `uname -sm` (`ax ssh` protocol) | **Yes** (live) |

*Note: Live tests automatically skip themselves if the Apple `container` CLI is not present or the daemon is not running.*

To run the entire repository test suite:
```bash
go test ./...
```

---

## 2. Full Local Stack Walkthrough (~2 minutes)

This workflow runs the real AX stack and tests Task creation, resumption, and container execution via `ax ssh`:

### Step 2.1: Start the local stack
```bash
make local-up
```
*(Or: `./examples/ate_local/local-stack.sh up`)*

This helper automatically:
1. Validates prerequisites and verifies ports are free.
2. Builds all binaries (`ax`, `ax-server`, `ate-local`, and an arm64 `ax-task-runner`).
3. Starts Valkey in an isolated Apple container (`valkey/valkey:8-alpine`).
4. Starts `ate-local` on port 50051.
5. Starts `ax-server` on port 8090 (with direct Substrate reconciliation).
6. Generates environment settings in `.ax-local/env`.

### Step 2.2: Point your CLI at the local stack
```bash
source .ax-local/env
make local-status
```
You should see all three components reporting `STATE: running` and `REACHABLE: yes`.

### Step 2.3: Apply and run a Task
```bash
# 1. Submit the local task specification (debian:12 with arm64 runner)
ax apply -f examples/ate_local/task-local.yaml

# 2. Upstream AX tasks are created Suspended by default:
ax get tasks

# 3. Resume the task to start the Apple container:
ax resume local-task

# 4. Check the task status:
ax describe task local-task
```

Expected `describe` output:
```text
Name:         local-task
Atespace:     default
Phase:        Running
Actor:        local-task
Worker IP:    192.168.64.x
Image:        debian:12

Conditions:
  TYPE            STATUS  REASON         MESSAGE
  Ready           True    TaskRunning    Task is running and its workspace is ready
  WorkspaceReady  True    SetupComplete  Workspace setup completed at 192.168.64.x
```

### Step 2.4: Execute commands inside the container via `ax ssh`
```bash
# Verify the kernel and architecture inside the Apple container
ax ssh local-task -- uname -sm
# Output: Linux aarch64

# Check the guest OS release
ax ssh local-task -- cat /etc/os-release
# Output: Debian GNU/Linux 12 (bookworm)

# View active containers directly via macOS CLI
container list
```

### Step 2.5: Tear down
```bash
# Delete the task (also tears down the container)
ax delete task local-task

# Stop the entire local development stack
make local-down
```

---

## 3. Control-Plane-Only Demo (~30 seconds)

If you only want to test `ate-local`'s Substrate Control API without running `ax-controller` or `ax-server`:

```bash
# Ensure the full stack is stopped first (both use port 50051)
make local-down 2>/dev/null || true

./examples/ate_local/run_demo.sh
```

**What this does:**
1. Starts `ate-local` standalone in the background.
2. Executes `demo_client.go` to call `CreateActor`, `ResumeActor`, `SuspendActor`, and `DeleteActor`.
3. Verifies both HTTP `/readyz` (port 80) and gRPC (port 50053) on the returned `192.168.64.x` bridge IP.
4. Stops and cleans up.

---

## Helper Script Reference (`local-stack.sh`)

| Command | Purpose |
|---|---|
| `make local-up` | Starts Valkey, `ate-local`, and `ax-server` in strict dependency order. Safe to run multiple times (idempotent). |
| `make local-status` | Displays running status, PIDs, listening ports, reachability, and active `ate-*` containers. |
| `make local-logs` | Follows logs from all components (`.ax-local/logs/*.log`). |
| `./examples/ate_local/local-stack.sh logs ate-local` | Follows the log of a specific component (`ate-local`, `ax-server`, or `valkey`). |
| `make local-down` | Gracefully stops components in reverse dependency order and removes the Valkey container. |
| `make local-down --keep-valkey` | Stops AX processes but keeps the Valkey container running to preserve task history. |
| `make local-reset` | Stops all processes, force-removes any leftover `ate-*` containers, and restarts the stack fresh. |

You can override default ports using environment variables:
```bash
export AX_LOCAL_REDIS_PORT=6380
export AX_LOCAL_SUBSTRATE_PORT=50052
export AX_LOCAL_SERVER_PORT=8091
make local-up
```

---

## Troubleshooting

| Symptom | Cause & Fix |
|---|---|
| `port N (needed by X) is in use by ...` | Another process is holding port 6379, 50051, or 8090. Stop the competing process or specify an alternate port via `AX_LOCAL_*_PORT`. |
| `http2: frame too large ... looked like an HTTP/1.1 header` | `ax` was executed without `--server` or without `AX_SERVER` set, causing it to fall back to `localhost:8080` (which is often held by local web/inference servers like diffgemma). Run `source .ax-local/env` or pass `--server localhost:8090`. |
| Task status stays `Suspended` | Upstream AX tasks default to `Suspended` upon creation. Run `ax resume <task-name>`. |
| Task phase is `Pending` with `SubstrateUnavailable` | `ate-local` was not yet listening when `ax-server` attempted reconciliation. `ax-server` automatically retries transient Substrate transport errors with backoff. Run `ax resume <task-name>` once `ate-local` is up. |
| `ax ssh <task> -- uname -a` | Fixed upstream in PR #411 / #413. Flags after `--` are now passed untouched to the guest command. |
| Upstream `examples/simple.yaml` fails to run | The official `ax-task-runner` image is published only for `linux/amd64`. On Apple Silicon, use `examples/ate_local/task-local.yaml` (which uses `debian:12` and mounts our arm64 runner). |
| Stale state between Valkey and `ate-local` | Run `make local-reset` to clean up and re-initialize both simultaneously. |

---

## Known Limitations of `ate-local` (v1)

1. **Cold Start Lifecycle (No Process Memory Snapshots)**:
   Apple `container` currently lacks a user-space memory checkpoint/restore primitive (such as `runsc --checkpoint`). In `ate-local`, `SuspendActor` stops the container (`container stop`), and `ResumeActor` restarts/boots it. This matches the **"Clean start from OCI"** and **"Disk-only resume"** modes outlined in Substrate's roadmap, but volatile in-RAM state is not preserved across hibernation.
2. **Single-Node macOS Scope**:
   Designed exclusively for local development on Apple Silicon. Does not support multi-node scheduling or cross-host migration.
3. **Architecture**:
   Apple `container` runs `linux/arm64` virtual machines. Container images published exclusively for `linux/amd64` must be built for `arm64`.
4. **No Identity/Proxy Mesh**:
   Bypasses Envoy `ext_proc` routing and SPIFFE mTLS, providing direct connectivity to the container's `vmnet` bridge IP.

---

## Questions for Discussion with Colleagues

1. **Project Placement**:
   - Option A: Live in **`google/ax`** (e.g. `cmd/ate-local/` or `internal/substrate/local/`) as the official zero-cluster local developer runtime.
   - Option B: Live in **`agent-substrate/substrate`** as a native macOS local control-plane driver alongside the existing `kind` cluster setup.
   - Option C: Standalone companion repo (`ate-local` or `ax-local`).
2. **Eliminating the Redis Requirement**:
   - Would an in-process `ax dev` command (combining `ax-server` and `ax-controller` using AX's existing in-memory store) be preferable to avoid running Valkey locally?
3. **Persistent Volume Binding**:
   - Should `ate-local` automatically provision a host directory bind (e.g. `~/.ax/volumes/<actor-id>/workspace`) so that workspace edits persist across `SuspendActor` and `ResumeActor` cycles?

---

*Please share your feedback, questions, or test results directly on the internal thread!*
