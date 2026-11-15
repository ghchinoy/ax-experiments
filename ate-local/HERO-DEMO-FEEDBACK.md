# `ate-local` Field Report & Handoff from the 5/5 Live Hero Demo (`#590` / `#602`)

> **OKF v0.2 Track Metadata**: [`okf/ate-local.md`](../okf/ate-local.md) · **Hero Demo Card**: [`okf/hero-demo.md`](../okf/hero-demo.md) · **Target Branch**: [`ghchinoy/ax:feat/ate-local-apple-container`](https://github.com/ghchinoy/ax/tree/feat/ate-local-apple-container)

This document captures the edge cases, fixes already landed in [`ghchinoy/ax@471ca83`](https://github.com/ghchinoy/ax/commit/471ca83), and remaining follow-up work for the **`ate-local` fork agent (`~/projects/ax`)** uncovered while bringing upstream [`google/ax/hack/hero-demo/`](https://github.com/google/ax/pull/590) to **`5/5 🟢 PASS`** in [`hero-demo/run-live.sh`](../hero-demo/run-live.sh).

---

## 1. Landed Fixes in `ghchinoy/ax@471ca83` (Do Not Revert on Rebase)

### A. Pre-Boot Workspace Snapshot Hydration (`internal/atelocal/server.go` — `stagePreBootWorkspace`)
- **Symptom**: Previously, `ResumeActor` called `restoreWorkspaceSnapshot` (`container exec ... tar -xzf - -C /workspace`) *after* `container run` and `waitForPort(:80)`. Because PID 1 (`/usr/local/bin/ax-task-runner`) runs `workspace.SetupWorkspace` immediately on container startup (before `/readyz` turns `200`), a task attaching to a pre-warmed workspace saw an empty `/workspace` at `T=0` and re-ran `spec.setup.commands`.
- **Why Hero Demo Step 4 Exposed It**: Upstream `hack/hero-demo/workspace.yaml` runs `git init /workspace/app` in `spec.setup.commands`, while `hack/hero-demo/task-custom.yaml` runs stock `python:3.12-slim` (which has **no `git` binary** and runs `commands: ["python3", "-m", "unittest", ...]`). Without pre-boot hydration, `ax-task-runner` attempted `git init` inside `python:3.12-slim` and failed with `exec: "git": executable file not found in $PATH`.
- **Fix Landed (`471ca83`)**: `stagePreBootWorkspace(actor, tmpl)` checks for `<SnapshotDir>/<atespace>/<actor>.tar.gz`, `tags/<SourceTag>.tar.gz`, or `tags/<workspace>-warm.tar.gz` before `container run` / `podman run`, extracts the archive into `<SnapshotDir>/workdirs/<prefix>/<atespace>/<actor>`, and appends `-v <hostDir>:/workspace` so `.ax/setup-complete` and `/workspace/app` exist at `T=0` before PID 1 starts.

### B. `ax-server` Prometheus `--metrics-addr` Port Collision in `multi-up` (`examples/ate_local/local-stack.sh`)
- **Symptom**: Upstream `#579` added `--metrics-addr` defaulting to `:9090` in `cmd/ax-server/main.go`. Running `local-stack.sh multi-up` (Cluster A + Cluster B) or launching an isolated test stack failed when the second `ax-server` tried to bind `:9090` (`listen tcp :9090: bind: address already in use`).
- **Fix Landed (`471ca83`)**: `local-stack.sh` now passes `--metrics-addr 127.0.0.1:9090` for default Cluster A (`:8090`), `--metrics-addr 127.0.0.1:9091` for default Cluster B (`:8091`), and `--metrics-addr ""` (or `AX_LOCAL_METRICS_PORT` / `AX_LOCAL_METRICS_B_PORT`) on custom-port stacks.

### C. Cold PostgreSQL Database Init Race (`examples/ate_local/local-stack.sh`)
- **Symptom**: On a brand-new `postgres:17-alpine` container, `pg_isready -U ax -d ax` returns `0` briefly while the entrypoint is still running initdb before `CREATE DATABASE ax` completes, causing `multi-up`'s `CREATE DATABASE ax_cluster_b` to fail with `FATAL: database "ax" does not exist`.
- **Fix Landed (`471ca83`)**: `start_postgres()` now polls `psql -U ax -d ax -c "SELECT 1"`.

---

## 2. Actionable Follow-Ups for the `~/projects/ax` Agent

### Follow-Up 1: Clean Up Staged `workdirs/` on `DeleteActor` & Host-Fallback Snapshot Archiving (`internal/atelocal/server.go`)
1. **`DeleteActor` cleanup**: When `DeleteActor` deletes an actor (`internal/atelocal/server.go:937`), also remove `<SnapshotDir>/workdirs/<prefix>/<atespace>/<actor>` (and optionally decide whether `<SnapshotDir>/<atespace>/<actor>.tar.gz` should be removed on explicit `DeleteActor` so a deleted-and-recreated task starts clean from `<workspace>-warm.tar.gz` rather than stale deleted-task state!).
   - *Important*: Right now, if a user runs `ax delete task foo` and then `ax apply -f foo.yaml`, a leftover `<SnapshotDir>/<atespace>/foo.tar.gz` from the deleted task will hydrate into the new `foo` task unless `DeleteActor` cleans it up!
2. **Host-directory fallback in `saveWorkspaceSnapshot`**: When `stagePreBootWorkspace` mounted `-v <hostDir>:/workspace`, `saveWorkspaceSnapshot` (`internal/atelocal/server.go:815`) can archive directly from `<hostDir>` on the host if `container exec ... tar` fails (for instance, if a container exited before `SuspendActor` was called), and add a unit test in `internal/atelocal/server_test.go` covering real gzip archive pre-boot staging + `DeleteActor` cleanup.

### Follow-Up 2: Automatic Workspace Pre-Warm `Tag` & `WorkspaceSpec.profile` Support (`internal/server/workspace.go` + `examples/ate_local/`)
1. **Unblock `WorkspaceSpec.profile` (`#584`)**: Upstream `hack/hero-demo/workspace.yaml` sets `spec.profile.resources`, which `firstUnimplementedWorkspaceField` in `internal/server/workspace.go:154` currently rejects with `codes.Unimplemented: spec.profile is not supported yet`.
2. **Auto-Prewarm on `CreateWorkspace` (or `TaskReconciler`)**: Currently [`hero-demo/run-live.sh`](../hero-demo/run-live.sh) runs a temporary setup task (`hero-demo-ws-prewarm`) and [`genkit/cmd/ws-tag`](../genkit/cmd/ws-tag/main.go) to mint `Tag` `hero-demo-ws-warm`. Wiring `CreateWorkspace` (when `spec.setup` is non-empty) to run a short-lived setup actor on `ate-local` (using `spec.profile.image` or a git-capable default setup image) and call `CreateTag(<ws>-warm)` automatically will allow upstream's unmodified `hack/hero-demo/run.sh` Step 2 & Step 4 to turn `🟢 PASS` without any external helper!

### Follow-Up 3: Upstream `hack/hero-demo/run.sh` Wiring on `feat/ate-local-apple-container`
- With Follow-Ups 1 & 2 in place, `hack/hero-demo/run.sh` in `~/projects/ax` can wire Steps 1–5 directly against `examples/ate_local/local-stack.sh multi-up` (verify by running `~/projects/ax-experiments/hero-demo/run-live.sh` as the regression gate).
