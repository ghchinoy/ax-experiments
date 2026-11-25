# End-to-End 5/5 Live AX v0.1 Hero Demo Harness (`hero-demo/`)

> **OKF v0.2 Concept Card**: [`okf/hero-demo.md`](../okf/hero-demo.md) · **Upstream Harness**: [`google/ax#590`](https://github.com/google/ax/pull/590) (`hack/hero-demo/`) · **Local Substrate**: [`google/ax#602`](https://github.com/google/ax/issues/602)

Upstream [`google/ax/hack/hero-demo/run.sh`](https://github.com/google/ax/pull/590) defines the five-step **AX v0.1 Hero Demo** scoreboard, where four steps remain `🟡 STUB`s on upstream `main` while local mode (`#526`/`#602`), warm workspace snapshots (`#584`), multi-turn starter sessions, and automatic `ax-task-runner` injection land.

This directory executes **all 5 steps live end-to-end (`5/5 🟢 PASS`)** by combining:
- **[`ghchinoy/substrate-local`](https://github.com/ghchinoy/substrate-local)** (graduated from [`ate-local`](/ate-local/README.md), [`google/ax#602`](https://github.com/google/ax/issues/602)) with pre-boot warm `Tag` snapshot hydration, embedded `atenet-router`, automatic `/usr/local/bin/ax-runner` injection on stock images, and dual-cluster `Apple container` $\leftrightarrow$ `Podman` promotion against **unmodified upstream `google/ax`**;
- **[`ghcr.io/ghchinoy/ax-images/genkit-runner`](https://github.com/ghchinoy/ax-images)** (`v0.3.0`, multi-arch `@sha256:` pinned) with persistent `/workspace/.genkit/snapshots` multi-turn sessions across `ax suspend` and `ax resume`; and
- **[`AX Central`](https://github.com/ghchinoy/ax-central)** (`~/projects/ax-central`) desktop control plane.

---

## Quickstart

```bash
export GEMINI_API_KEY="your-key"   # optional; runs deterministic offline verification if unset
make hero-demo                     # or: ./hero-demo/run-live.sh
```

By default, `run-live.sh` spins up an **isolated dual-cluster stack** (`Cluster A`: Apple `container` on `:8097`/`:50071`, `Cluster B`: Podman on `:8098`/`:50072`, isolated Postgres on `:5445`) so it never disturbs an active local stack on `:8090`, and tears down cleanly on exit.

### CLI Flags

```bash
./hero-demo/run-live.sh                           # Isolated 5/5 live run (default)
./hero-demo/run-live.sh --attach                  # Run against active substrate-local ax-stack.sh multi-up (:8090 / :8091)
./hero-demo/run-live.sh --step 4                  # Run a single step
./hero-demo/run-live.sh --remote-context <ctx>    # Promote Step 5 to a Kubernetes Kind/GKE context
./hero-demo/run-live.sh --keep-stack              # Leave isolated dual-cluster stack up for inspection
```

---

## Live 5/5 Scoreboard & What Each Step Verifies

| Step | Manifest | How `run-live.sh` Replaces Upstream's `🟡 STUB` with `🟢 PASS` |
|---|---|---|
| **1. Local Up & Studio** | *(control plane)* | Boots dual-cluster `ate-local` (`Cluster A` Apple `container` + `Cluster B` Podman) with embedded `atenet-router` and verifies `ax get workspaces` + AX Central / Studio health. |
| **2. Warm Workspace Snapshot** | [`workspace.yaml`](./workspace.yaml) | Applies `hero-demo-ws` (`spec.setup.commands` running `git init /workspace/app` and creating `math_utils.py` + `test_math.py`), mints immutable Agent Substrate v1.0 `Tag` `hero-demo-ws-warm` (`SNAPSHOT_STORAGE_STATE_COMPLETED`) via [`genkit/cmd/ws-tag`](../genkit/cmd/ws-tag/main.go), and verifies warm wake-on-request (`HTTP 200`) through `atenet-router`. |
| **3. Starter Task, Session & Resume** | [`task-starter.yaml`](./task-starter.yaml) | Runs digest-pinned `ghcr.io/ghchinoy/ax-images/genkit-runner@sha256:2620b7bc...`: **Turn 1** (`contextId="hero-demo-session"`) implements `subtract(a, b)` and `test_subtract`; `ax suspend task` $\rightarrow$ `ax resume task` cold-boots a new microVM; **Turn 2** recalls `'subtract'` from `/workspace/.genkit/snapshots` without re-reading files. |
| **4. Custom Image Task** | [`task-custom.yaml`](./task-custom.yaml) | Runs upstream's **unmodified** `image: python:3.12-slim` + `commands: ["python3", "-m", "unittest", "discover", "-s", "/workspace/app", "-p", "test_*.py"]`. Because `python:3.12-slim` has neither `ax-task-runner` nor `git`, passing `2/2` tests (`OK`) proves both automatic runner injection and warm snapshot hydration (`workspace already initialized; skipping maiden run setup`). |
| **5. Remote Cluster Promotion** | `workspace.yaml`, `task-custom.yaml` | Applies the exact same manifests unchanged to **Cluster B** (`Podman` runtime on `localhost:8098`, or `--remote-context` Kubernetes cluster), resumes `hero-demo-custom-task`, and verifies `Ran 2 tests ... OK` on the promoted target cluster. |

### Measured Output (Apple Silicon M5 + Podman + Gemini 3.8 Flash)

```text
================================================================================
  AX v0.1 HERO DEMO SCOREBOARD (live — 5/5 end-to-end)
================================================================================
  1. Local Up & Studio               | 🟢 PASS | Cluster A (localhost:8097) + atenet-router (127.0.0.1:50071) up; AX Central desktop control plane verified (/Users/ghchinoy/projects/ax-central)
  2. Warm Workspace Snapshot         | 🟢 PASS | Tag hero-demo-ws-warm COMPLETED & warm wake-on-request HTTP 200 verified via atenet-router
  3. Starter Task, Session & Resume  | 🟢 PASS | Starter image ran Turn 1, survived suspend/resume, and recalled 'subtract' on Turn 2 (live-gemini)
  4. Custom Image Task               | 🟢 PASS | Unmodified python:3.12-slim ran injected ax-task-runner, skipped git setup via warm snapshot, and passed 2/2 unit tests (exitCode=0)
  5. Remote Cluster Promotion        | 🟢 PASS | Promoted unchanged manifests from Cluster A (apple) to Cluster B (podman localhost:8098) & passed 2/2 unit tests (exitCode=0)
================================================================================
```
