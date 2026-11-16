# `ate-local` Field Report & Handoff from the 5/5 Live Hero Demo (`#590` / `#602`)

> **OKF v0.2 Track Metadata**: [`okf/ate-local.md`](../okf/ate-local.md) · **Hero Demo Card**: [`okf/hero-demo.md`](../okf/hero-demo.md) · **Target Branch**: [`ghchinoy/ax:feat/ate-local-apple-container`](https://github.com/ghchinoy/ax/tree/feat/ate-local-apple-container)

This document captures the edge cases, fixes landed in [`ghchinoy/ax@471ca83`](https://github.com/ghchinoy/ax/commit/471ca83), and the three follow-up items for the **`ate-local` fork branch (`~/projects/ax`, `feat/ate-local-apple-container`)** uncovered while bringing upstream [`google/ax/hack/hero-demo/`](https://github.com/google/ax/pull/590) to **`5/5 🟢 PASS`** in [`hero-demo/run-live.sh`](../hero-demo/run-live.sh). All three follow-ups in Section 2 have since landed on `feat/ate-local-apple-container` (rebased onto `google/ax:main` at `b95c3f4`).

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

## 2. Follow-Ups Landed on `feat/ate-local-apple-container`

### Follow-Up 1 (`✅ Landed` — `8cb98dd` / rebased `4ef71a5`): Clean Up Staged `workdirs/` on `DeleteActor` & Host-Fallback Snapshot Archiving (`internal/atelocal/server.go`)
1. **`DeleteActor` cleanup**: `DeleteActor` now removes both `<SnapshotDir>/workdirs/<prefix>/<atespace>/<actor>` and `<SnapshotDir>/<atespace>/<actor>.tar.gz` while preserving shared `<SnapshotDir>/<atespace>/tags/*.tar.gz` archives, ensuring a deleted-and-recreated task starts clean from `<workspace>-warm.tar.gz` rather than stale deleted-task state.
2. **Host-directory fallback in `saveWorkspaceSnapshot`**: When `stagePreBootWorkspace` mounted `-v <hostDir>:/workspace`, `saveWorkspaceSnapshot` now archives directly from `<hostDir>` on the host (`archiveDirTarGz`) if `container exec ... tar` fails (for instance, when a batch container like `python:3.12-slim` exits before `SuspendActor` is called), covered by `TestPreBootWorkspaceStagingAndDeleteCleanup` in `internal/atelocal/server_test.go`.

### Follow-Up 2 (`✅ Landed` — `8cb98dd` & `eb8a693` / rebased `4ef71a5` & `a7607d4`): Automatic Workspace Pre-Warm `Tag` & `WorkspaceSpec.profile` Support (`internal/server/workspace.go` + `internal/atelocal/server.go`)
1. **Unblocked `WorkspaceSpec.profile.{image,resources}` (`#584`)**: `firstUnimplementedWorkspaceField` in `internal/server/workspace.go` now permits `spec.profile.image` and `spec.profile.resources` (enforced by `TaskReconciler.EffectiveProfile`), rejecting only `spec.profile.ateActorTemplate` and `spec.setup.gateway`.
2. **Lazy Auto-Prewarm on First Attach**: `ensureWarmWorkspaceTag` in `internal/atelocal/server.go` runs a short-lived setup container (using `ws.spec.profile.image` or `alpine/git`) when a task attaches to a `Workspace` with non-empty `spec.setup` and no `<ws>-warm` `Tag` snapshot exists yet, waiting for `.ax/initialized` and archiving `tags/<ws>-warm.tar.gz` automatically.

### Follow-Up 3 (`✅ Landed` — `eb8a693` / rebased `a7607d4`): Upstream `hack/hero-demo/run.sh` Wiring on `feat/ate-local-apple-container`
- `hack/hero-demo/run.sh` in `~/projects/ax` now supports `RUN_LIVE_STEPS=1 ATE_LOCAL=1` across all 5 steps directly against `examples/ate_local/local-stack.sh multi-up` (using digest-pinned `genkit-runner` for Step 3, unmodified stock `python:3.12-slim` with injected `ax-task-runner` + warm workspace snapshot for Step 4, and Cluster A $\rightarrow$ Cluster B promotion for Step 5).
