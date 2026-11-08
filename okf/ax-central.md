---
type: External Experiment
title: "Track 4: AX Central — Desktop Control Plane, Task Designer & Podman Shim"
description: "Standalone Wails v2 + Lit 3 + xterm.js + WebMCP desktop app (v0.4.0) for designing, deploying, migrating, and visualizing AX Tasks/Workspaces/Models, OTel trace waterfalls, and shimming docker-to-podman."
status: stable
tags: [ax-central, wails, lit, xterm, webmcp, podman, otel, desktop, external]
generated:
  by: human:ghchinoy
  at: 2026-11-01T00:00:00Z
verified:
  - by: human:ghchinoy
    at: 2026-11-08T00:00:00Z
sources:
  - id: upstream-ax
    resource: https://github.com/google/ax
    title: "google/ax: Agent Executor"
  - id: upstream-substrate
    resource: https://github.com/agent-substrate/substrate
    title: "agent-substrate/substrate: Agent Substrate"
experiment:
  track: ax-central
  location: external
  local_path: ~/projects/ax-central
  beads:
    - ax-experiments-bxv
  entrypoints:
    - Makefile
    - wails.json
    - app.go
    - shell.go
    - docker-shim.sh
    - hack/doctor.sh
    - hack/smoke-local.sh
    - docs/index.md
  upstream:
    repo: google/ax
    base_commit: f0228f1
---

# Track 4: AX Central (`~/projects/ax-central`)

## Hypothesis & Goal

Provide a native desktop control center (**Wails v2 + Go + Lit 3 WebComponents + `@xterm/xterm` + WebMCP**) to design, deploy, and inspect AX `Task`, `Workspace`, and `Model` resources across local and cluster environments, while transparently shimming `docker` and `docker buildx` to **Podman** for machines without Docker Desktop.[^upstream-ax][^upstream-substrate]

## External Project Structure (`~/projects/ax-central`)

- `wails.json` & `app.go` — Wails v2 native desktop shell (`v0.4.0`), file dialogs, and atespace `TraySummary` grouping tasks by lifecycle phase.
- `shell.go` — Streaming command runner, `Shell.Pipe` OS-pipe bridge (`FromProgram`/`FromEnv` $\rightarrow$ `ToProgram`/`ToEnv`), interactive stdio terminal sessions (`ax ssh`), and container runtime detection (`docker` vs. `podman`).
- `docker-shim.sh` — Embedded `docker` → `podman` shim for `kind`, Agent Substrate, and AX build scripts (skips TLS on `localhost`/`127.0.0.1` Kind registries, preserves pushed manifest digests across Podman layer recompression, and emulates `docker buildx build --push --metadata-file` / `imagetools inspect`).
- `frontend/src/model/` — TypeScript state stores for clusters (`clusters.ts`), declarative YAML task design with `ax-images` v0.5.0 presets (`designer.ts`), cross-substrate and cross-atespace `Move Task` (`move.ts`), and live AX resources (`resources.ts`, `store.ts`).
- `frontend/src/views/` & `tools.ts` — Activity (`<ax-overview>`, `<ax-task-inspector>`, `<ax-task-logs>` with `All`/`Guest`/`Substrate`/`OTel` filters, cgroup/RustFS telemetry strip, and Jaeger v2 + Genkit OpenTelemetry trace waterfalls), Map (`<ax-topology>` with `AX_TARGETS` router-to-specialist Bezier edges), Deploy (`<ax-designer>`), Terminal (`<ax-terminal>`), Clusters (`<ax-clusters>`), and 17 WebMCP tools (`<ax-webmcp-drawer>`).

## Verification & Build Commands (in `~/projects/ax-central`)

```bash
cd ~/projects/ax-central
make doctor         # audit go, Apple container, ax ate-local variant, ax-experiments & kind
make check          # gofmt, go vet, golangci-lint, bash -n, tsc, prettier, npm audit, Go & Vitest tests
make smoke-local    # E2E debian:12 task smoke test against local Apple container stack
make build          # npm run build + go build -o ax-central .
make dev            # wails dev live-reload session
```

## Related Experiment Tracks

- Connects to local stacks managed by [Track 1: Local Apple Container Substrate (ate-local)](/ate-local.md) or Podman/Kind clusters.
- Designs and launches workloads exercised in [Track 2a: Multi-Agent Swarm Recipes (01–08)](/swarm.md) and [Track 2b: Declarative Genkit Go Runner (genkit-runner)](/genkit.md).
- Complements the swarm execution trace replayer in [Track 3: Swarm Telemetry, Correlation IDs & Visual Replay](/viz.md).

[^upstream-ax]: google/ax: Agent Executor
[^upstream-substrate]: agent-substrate/substrate: Agent Substrate
