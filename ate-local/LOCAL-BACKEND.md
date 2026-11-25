# `ax local` Backends: Kind Bring-Up Timings and `local.Backend` Options

> **OKF v0.2 Track Metadata & Lineage**: [`okf/ate-local.md`](../okf/ate-local.md) · **Beads**: `ax-experiments-1rx.3` (Phase A, this doc), `ax-experiments-1rx.6` (Phase B prototype)

Upstream merged a Kind-based `ax local start | status | stop | delete` in [google/ax#603](https://github.com/google/ax/pull/603), and [google/ax#689](https://github.com/google/ax/issues/689) reports that a fresh `ax local start` takes 3–5 minutes but has no per-step timing. This doc does two things:

1. Records a step-by-step timing of `ax local` v0.4.0-rc.1 on an Apple Silicon Mac (cold start, stop/resume, delete/recreate) next to the `ate-local` stack, answering the open question in #689.
2. Compares two ways to make `ax local` fast on macOS: a `local.Backend` seam that can select `ate-local` (Option A, the `ax local --backend=ate-local` direction in [`AX-SETUP.md`](./AX-SETUP.md)), and optimizing the Kind path (Option B).

## Summary

- **A fresh `ax local start` takes about 128 seconds** on an M5 with Podman when the Kind node image is cached. Image pulls are not the bottleneck: a recreate that pulled every Substrate and AX image again took 129 seconds. The time goes to readiness waits that run one after another. One of three fresh runs took 1059 seconds, 945 of them silent inside the control-plane rollout wait, and did not reproduce.
- **`ax local stop` followed by `start` is slower than `delete` followed by `start`** (170–362 s vs 128 s). After the node restarts, pod-certificate volumes cannot mount until `podcertificate-controller` recovers, kubelet's mount backoff adds about 90 seconds, and `alreadyHealthy`'s serial 90-second waits can expire and trigger a full re-bootstrap.
- **`ate-local` brings up the same AX API in 2.7 seconds** (7.8 s including a first build), about 47 times faster than a fresh Kind cluster, without a Podman machine, rootful mode, or Kubernetes.
- **Per task, Kind is not slower.** On a running cluster, resume to `Working` takes 0.10–0.14 s and the first `ax ssh` returns at 0.16–0.41 s, against 0.45–0.61 s to `Working` on `ate-local`, which boots a new microVM on each resume. `ate-local`'s advantage is bring-up, not the task inner loop.
- **Recommendation: do both.** Fix the Kind path first, starting with resume ([google/ax#689](https://github.com/google/ax/issues/689)), because it helps every platform. Add `ate-local` as an opt-in `--backend=ate-local` after google/ax#688 and #696 shrink it (`ax-experiments-1rx.5`, then `1rx.6`).

## Test Setup

| | |
| :--- | :--- |
| Host | Apple M5, 32 GiB, macOS 26.7.3 |
| `ax` | [v0.4.0-rc.1](https://github.com/google/ax/releases/tag/v0.4.0-rc.1) release binary (`ax_darwin_arm64.tar.gz`, checksum verified), contains upstream `0b44e97` |
| Images | Release digests: `ghcr.io/google/ax/ax-server@sha256:95737151…`, `ghcr.io/google/ax/ax-runner-volume@sha256:ac849f83…` |
| Substrate | v1.0.0 (embedded in `ax`), local profile, 1 gVisor worker |
| Kind | kind v0.33.0, `kindest/node:v1.36.1`, Podman 6.1.4 machine (libkrun, 5 CPUs, 8 GiB) over its **rootful** connection |
| `ate-local` | [`ghchinoy/ax@bfd5042`](https://github.com/ghchinoy/ax/tree/feat/ate-local-apple-container) (rebased on `0b44e97`, Substrate v1.0.0 Control API), Apple `container` 1.0.0, `postgres:17-alpine` |
| Isolation | Own `KUBECONFIG`, `AX_HOME`, and cluster name (`ax-bench`); `ate-local` on alternate ports and `AX_LOCAL_DIR` |

Every output line was timestamped as it arrived, so the step durations below are the gaps between the `==>` markers that `ax local start` prints. The harness is [`bench/ax-local-timing.sh`](./bench/ax-local-timing.sh).

## Results: `ax local` (Kind) vs `ate-local`

Measured on 2026-11-21. Multiple values are separate runs.

| Phase | `ax local` (Kind on Podman) | `ate-local` (`local-stack.sh`) |
| :--- | :--- | :--- |
| Container runtime ready | 8.6 s (`podman machine start`; rootful connection required) | Apple `container` system service, already running |
| Fresh environment, nothing cached | 1059.4 s (outlier, see [Finding 3](#3-one-cold-run-stalled-silently-for-16-minutes)); the Kind node image download alone is 16.3 s | 7.79 s (includes 5.1 s of `go build` into an empty bin dir) |
| Fresh environment, images cached on the host | 129.3 s, 128.0 s | 2.68 s, 2.71 s, 2.70 s |
| `status` | 0.5–0.7 s | 0.08 s |
| `stop` | 10.4 s | 5.3 s (`down`, which also deletes the Postgres container) |
| `start` after `stop` | 362.4 s, 169.5 s | 2.7 s (same path as a fresh start) |
| `delete` | 11.2 s | Included in `down` |
| Task resume → `Working` | 0.14 s, 0.10 s | 0.61 s, 0.45 s, 0.50 s |
| First `ax ssh` after resume | 0.41 s, 0.16 s (warm `ax ssh` 0.06 s) | Fails at `bfd5042` (`ax-experiments-1rx.7`) |

### Where a Fresh Kind Start Spends Its Time

Durations between the `==>` markers of the two fresh runs with a cached node image. The 128.0 s run followed a Podman VM reboot. In the 129.3 s run, `kind delete` had removed the node's `/var` volume, so every Substrate and AX image was pulled again.

| Step | 128.0 s run | 129.3 s run | Waits for |
| :--- | ---: | ---: | :--- |
| Kind cluster | 27.3 s | 26.9 s | `kind create cluster`, node `Ready`, kubeconfig context |
| Substrate namespaces, CRDs, CA pools, `podcertificate-controller`, SandboxConfig | 14.9 s | 12.5 s | CRDs `Established`, controller rollout, ClusterTrustBundles |
| Substrate PostgreSQL and mTLS roles | 15.0 s | 15.1 s | `postgres-0` `Ready`, schema and roles |
| Control plane, router, credential provider | 41.6 s | 44.5 s | Seven rollouts, awaited one at a time |
| gVisor WorkerPool | 4.0 s | 5.0 s | WorkerPool ready |
| AX permissions | 0.3 s | 0.2 s | — |
| `ax-postgres` | 16.8 s | 15.8 s | StatefulSet rollout |
| `ax-server` | 8.0 s | 9.0 s | Deployment rollout |
| **Total** | **128.0 s** | **129.3 s** | |

The `ate-local` equivalent, from a warm `up`: binary freshness check 0.8 s, Postgres container 1.1 s, `ate-local` 0.3 s, `ax-server` 0.2 s.

## Findings

### 1. `ax local` Rejects the Default Podman Machine

A Podman machine is rootless by default, and `ax local start` exits at once:

```text
Error: rootless Podman is not supported for 'ax local' (Kind node sysctls and Substrate's atelet DaemonSet require rootful mode): switch Podman Machine to rootful ('podman machine stop && podman machine set --rootful && podman machine start') or use Colima / OrbStack / Docker Desktop
```

Every Podman machine already serves a rootful socket as the `<machine>-root` connection, so `CONTAINER_CONNECTION=podman-machine-default-root ax local start` works without changing the machine or its default image store. This benchmark used that connection. `ax` could suggest it in the error, or select it itself when it exists.

### 2. Image Pulls Are Not the Bottleneck; Serial Waits Are

The 129.3 s recreate pulled every image again into a new node and finished the control-plane step in 44.5 s, about the same as the 128.0 s run. Pulls overlap with the readiness waits that already dominate:

- Two independent PostgreSQL instances, Substrate's (15 s) and AX's (16–17 s), start one after the other. `ax-postgres` depends only on its namespace and Secret.
- The seven control-plane workloads are applied together but awaited one at a time, each with its own 4-minute budget.
- Substrate's local profile also starts `rustfs`, Jaeger, an OpenTelemetry collector, and Prometheus. `ax local` doesn't wait for them, but they pull and start on the same 5 CPUs during bring-up.

### 3. One Cold Run Stalled Silently for 16 Minutes

The first run, the only one that also downloaded the Kind node image, spent 945 s between "Deploying Substrate control plane" and "Deploying gVisor WorkerPool". It printed a single line at the start:

```text
   86.25s      ate-system/deployment/ate-api-server is not ready: pod ate-api-server-799d88f774-4bvwg, container ate-api-server: PodInitializing
 1031.46s  ==> Deploying gVisor WorkerPool (1 replica(s))...
```

`executil.waitRollout` prints only when a waiting container reports a new reason, so a pod that is `Running` but not `Ready` produces no output. Each workload's 4-minute budget restarts, so seven slow workloads can wait up to 28 minutes without a word. The stall did not reproduce in two later fresh runs, one right after a Podman VM reboot (VM clock skew 0.6 s), and its cluster was deleted before its events could be read. The rerun harness samples pod states every 10 s for this reason. Whatever the cause, the user saw 16 minutes of silence, which is what [google/ax#648](https://github.com/google/ax/issues/648) is about.

### 4. Resuming a Stopped Cluster Is Slower Than Recreating It

The pod monitor and events from the 169.5 s resume show what happens after `ax local stop` and `start`:

1. The node restarts at 00:29:51. Every pod with a pod-certificate projected volume (`podidentity`, `servicedns`, `postgres`) fails to mount with `no credentials yet` and then `credential bundle is not issued yet`.
2. `podcertificate-controller`, which issues those credentials, goes into `BackOff` and isn't running again until 00:30:36.
3. By then kubelet's exponential mount retry has backed off, so `postgres-0` mounts its volumes only at 00:32:07, 2 minutes 16 seconds after the restart. `ate-api-server` and `atenet-router` depend on it and follow.
4. `alreadyHealthy` waits up to 90 s for `postgres-0`, then 90 s for each component in turn. In this run the first wait expired, so `ax local start` reran the whole bootstrap (94 s to 169 s). In the 362.4 s run every wait eventually passed, at the cost of six minutes.

### 5. The Task Inner Loop Is Already Fast on Kind

With a warm gVisor WorkerPool, resuming a suspended task to `Working` took 0.10–0.14 s and `ax ssh … uname -sm` returned 0.16–0.41 s after `ax resume`. `ate-local` takes 0.45–0.61 s to `Working` because it boots a new Apple container microVM per resume. For a developer who keeps one cluster running, Kind is not slower per task. The gap is bring-up and resume.

### 6. `ate-local` Regressions Found Along the Way

- `ax ssh` into an `ate-local` task fails at `bfd5042` with `starting process: rpc error: code = Internal desc = server closed the stream without sending trailers`, although resume, suspend, and delete work. Filed as `ax-experiments-1rx.7`.
- Actor containers are named `ate-<atespace>-<task>` with no stack prefix, so two `ate-local` stacks on one Mac share them: the isolated benchmark stack listed (and `down` warned about) the main stack's stopped `hero-demo` actors. An `ate-local` backend with `--name` needs a per-environment prefix.

## Why `ate-local` Is Not a `cluster.Provider`

`internal/install/cluster.Provider` is described as "Kind in MVP; native macOS VM in Phase 2", which reads like the place for an Apple-native backend. It is the wrong layer for `ate-local`:

```go
type Provider interface {
	Up(ctx context.Context, opts UpOptions) (Info, error) // Info{Name, KubeContext}
	Stop(ctx context.Context, name string) error
	Status(ctx context.Context, name string) (Status, error)
	Delete(ctx context.Context, name string) error
}
```

`runLocal` (`cmd/ax/install_cmd.go`) hard-wires three steps, and steps 2 and 3 take the `KubeContext` that `Up` returns:

1. `cluster.NewKindProvider(...).Up` creates or resumes the Kind cluster.
2. `installsubstrate.Bootstrap(KubeContext)` installs Agent Substrate (PKI, mTLS Postgres, control plane, gVisor WorkerPool).
3. `axdeploy.Install(KubeContext)` deploys `ax-postgres` and `ax-server` and grants Substrate caller access.

`ate-local` starts in seconds because it removes all three: there is no Kubernetes API server, `ate-local` itself serves the Substrate Control API (`ateapipb.ControlServer`) over Apple `container` microVMs, and `ax-server` runs as a host process against `postgres:17-alpine`. A `Provider` that returns no `KubeContext` would make steps 2 and 3 fail, and one that ran Kubernetes inside an Apple VM would keep most of the cost measured above. The seam has to sit above all three steps.

The CLI has the same assumption. `ax ctx` lists only kubeconfig contexts. The public `client` package from [google/ax#640](https://github.com/google/ax/pull/640) resolves the server as `Options.ServerURL`, then `$AX_SERVER`, then a `kubectl port-forward` to `svc/ax-server` recorded in `~/.ax/tunnels`, and its `ListContexts` reads kubeconfig. The fork works around this with `source .ax-local/env`, which exports `AX_SERVER` and `ATENET_ROUTER_ADDR`.

## Option A: A `local.Backend` Seam Above `cluster.Provider`

Introduce one interface for the whole local environment and keep today's code as its Kind implementation:

```go
// Package local manages a single-user AX environment for `ax local`.
package local

type Endpoint struct {
	Name        string
	Server      string // AX API address the CLI should use, e.g. http://127.0.0.1:8090
	KubeContext string // empty when the backend has no Kubernetes API server
}

type Backend interface {
	Start(ctx context.Context, opts StartOptions) (Endpoint, error)
	Stop(ctx context.Context, name string) error
	Status(ctx context.Context, name string) (cluster.Status, error)
	Delete(ctx context.Context, name string) error
}
```

- **`kind` (default)**: `Start` is today's `runLocal` body (`Provider.Up` → `Bootstrap` → `axdeploy.Install`). No behavior change.
- **`ate-local` (opt-in)**: `Start` is `local-stack.sh up` in Go, on Apple `container` microVMs (macOS 26 on Apple Silicon) or Podman, including rootless Podman (`AX_LOCAL_RUNTIME`).

`ax local start --backend=ate-local` maps onto the fork's stack like this:

| `ax local` | `ate-local` backend | Kind backend today |
| :--- | :--- | :--- |
| `start` | Run `postgres:17-alpine` in a container (named volume), start `ate-local` (Substrate Control API on a loopback port), start `ax-server --substrate-endpoint=<ate-local>`, wait for both ports, register an AX context with `Server` set | Create/resume Kind, bootstrap Substrate, deploy AX, select kube context |
| `status` | Process and port health for `ate-local`, `ax-server`, and the Postgres container, as `cluster.Status{Backend: "ate-local"}` | Node, Substrate, and AX rollout health |
| `stop` | Stop `ax-server` and `ate-local`, stop the Postgres container, keep its volume | `podman/docker stop` the node containers |
| `delete` | Delete task microVMs, the Postgres container and volume, and the state dir; drop the AX context | `kind delete cluster`, drop the kube context |

Two upstream changes would make this backend much smaller than the fork's `+5230` lines:

- **[google/ax#688](https://github.com/google/ax/pull/688) (push-runner)**: The runner moves into the task image and ax-server pushes work to it, so `ate-local` no longer has to mount a runner volume or build `ax-runner` for `linux/arm64`.
- **[google/ax#696](https://github.com/google/ax/issues/696) (no Workspace setup actors)**: Workspace setup stops creating its own actors, which removes the setup-actor lifecycle `ate-local` emulates today.

The CLI needs one addition either way: an AX context record that carries a server address (and router address) instead of a kube context, which `ax ctx` and `client.ListContexts` can list and `client.ServerURL` can resolve, so switching to an `ate-local` environment no longer needs `$AX_SERVER`. [`AX-SETUP.md`](./AX-SETUP.md) proposes keeping that record in `~/.ax/`.

**Costs and limits.** `ate-local` is a second implementation of the Substrate Control API that must track Substrate releases (it did so for v1.0.0 in `bfd5042`). It provides microVM isolation instead of gVisor, and no Kubernetes features: no `PodCertificateRequest` mTLS between components, no `atenet` router or egress policy, no WorkerPool scheduling. Its fastest runtime, Apple `container`, needs macOS 26 on Apple Silicon; the Podman runtime trades some of that speed for Linux and rootless support. These limits are acceptable for an inner-loop backend, but they mean the Kind backend stays the reference for anything that `ax promote` will run on a real cluster.

## Option B: Make the Kind Path Faster (google/ax#689)

In order of expected payoff on this machine:

1. **Fix resume.** On a stopped cluster, after the node is `Ready`, wait for `podcertificate-controller`, then delete the Substrate pods whose pod-certificate volumes failed to mount, so they remount immediately instead of waiting out kubelet's backoff. Run `alreadyHealthy`'s waits in parallel under one deadline instead of 90 s each in series. This should bring `start` after `stop` close to the node restart plus the control plane's own startup, instead of 170–362 s.
2. **Overlap independent steps.** Apply `ax-postgres` as soon as the cluster exists, in parallel with the Substrate bootstrap, and wait for the seven control-plane workloads together under one deadline. On the breakdown above that saves about 15 s for `ax-postgres` plus part of the 41–44 s control-plane step.
3. **Report progress for pods that are `Running` but not `Ready`** (#648): print elapsed time and per-pod readiness on each poll, so a stall like Finding 3 is visible and diagnosable.
4. **Preload images.** This matters less here because pulls already overlap the waits, but it may matter on slow networks and in CI.

These changes cannot reach seconds. A Kind cluster (about 27 s) plus Substrate's PKI, PostgreSQL, and control plane is a floor of roughly a minute on this hardware, an estimate rather than a measurement.

## Recommendation

1. **Option B now, upstream.** #689 asks for exactly this breakdown. Sharing the timings, the resume root cause (Finding 4), and the silent-wait gap (Finding 3) helps every platform, including Linux and CI.
2. **Option A as an opt-in `--backend=ate-local`, after #688 and #696.** It is the only path to a seconds-scale start, and on macOS the only one that needs no Podman machine or rootful engine. Kind stays the default and the reference for what `ax promote` targets. Rebase and simplify `ate-local` first (`ax-experiments-1rx.5`), then prototype `local.Backend` (`ax-experiments-1rx.6`).
3. **Prerequisites for proposing Option A upstream:**
   - AX context records that carry a server address, so `ax ctx` and the #640 `client` package can list and resolve a non-Kubernetes environment ([`AX-SETUP.md`](./AX-SETUP.md)).
   - A conformance test for the Substrate Control API, so a second implementation can't drift silently.
   - A per-environment actor prefix in `ate-local` (Finding 6).
   - A fix for `ax ssh` on `ate-local` (`ax-experiments-1rx.7`).

## Phase B Prototype Results (`ax-experiments-1rx.6`)

Implemented in [`ghchinoy/ax:feat/local-backend-atelocal`](https://github.com/ghchinoy/ax/tree/feat/local-backend-atelocal) (`d4ba29a`, branched from `473959a` / `google/ax@8d879b5`):

- **`internal/install/local/`**: `Backend` interface (`Start`, `Stop`, `Status`, `Delete`), `KindBackend` (default `--backend=kind`), and `AteLocalBackend` (`--backend=ate-local`) with per-environment state under `$AX_HOME/local/<name>/`, isolated Postgres container (`ax-<name>-postgres`), and per-environment actor prefix (`ate-<name>-`, closing Finding 6).
- **Non-K8s local endpoint contexts (`internal/tunnel/endpoints.go`)**: saves `$AX_HOME/endpoints/<name>.json` (`serverUrl`, `routerAddr`) and `$AX_HOME/current-context`, wired into `CurrentContext`, `ListContexts` (`ax ctx`), `SetCurrentContext`, `EnsureServerURL` (`pkg/client`), and `ax ssh` (`dialGuest`) — eliminating `source .ax-local/env`, `$AX_SERVER`, and `$ATENET_ROUTER_ADDR`.
- **Measured on Apple M5** (isolated ports `5446`/`50076`/`8099`, `KUBECONFIG` empty, `AX_SERVER` & `ATENET_ROUTER_ADDR` unset):

| Phase | `ax local --backend=kind` (`v0.4.0-rc.1`) | `ax local --backend=ate-local` (`d4ba29a`) | Speedup |
| :--- | ---: | ---: | ---: |
| Fresh start | 128.0–129.3 s | **1.77 s** | **~72×** |
| `stop` | 10.4 s | **5.30 s** | ~2× |
| `start` after `stop` (preserving Postgres) | 169.5–362.4 s | **0.86 s** | **~200–420×** |
| `delete` | 11.2 s | **5.43 s** | ~2× |
| Zero-env-var `apply` $\rightarrow$ `resume` $\rightarrow$ `ax ssh` | Works via kube context | **Works via `$AX_HOME/endpoints/`** (`Linux aarch64`) | Parity |

## Reproduce

```bash
# Kind backend (downloads ax v0.4.0-rc.1). Needs a rootful Podman connection,
# Colima, OrbStack, or Docker Desktop. Takes about 15 minutes.
podman machine start
CONTAINER_CONNECTION=podman-machine-default-root BENCH_DIR=/tmp/ax-bench \
  ate-local/bench/ax-local-timing.sh

# ate-local backend, on alternate ports so a running stack is untouched.
export AX_LOCAL_DIR=/tmp/ax-bench-atelocal AX_LOCAL_POSTGRES_PORT=5441 AX_LOCAL_SUBSTRATE_PORT=50061 \
  AX_LOCAL_SERVER_PORT=8096 AX_LOCAL_RUNNER_PORT=8085 AX_LOCAL_POSTGRES_NAME=ax-bench-postgres
time ~/projects/ax/examples/ate_local/local-stack.sh up
source "$AX_LOCAL_DIR/env"   # exports AX_SERVER and ATENET_ROUTER_ADDR
~/projects/ax/examples/ate_local/local-stack.sh down
```
