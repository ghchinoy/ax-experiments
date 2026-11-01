---
type: External Experiment
title: "Track 4: AX Central — Desktop Control Plane, Task Designer & Podman Shim"
description: "Standalone Wails v2 + Lit 3 + xterm.js + WebMCP desktop app for designing, deploying, and visualizing AX Tasks/Workspaces/Models and shimming docker-to-podman."
status: stable
tags: [ax-central, wails, lit, xterm, webmcp, podman, desktop, external]
generated:
  by: human:ghchinoy
  at: 2026-11-01T00:00:00Z
verified:
  - by: human:ghchinoy
    at: 2026-11-01T00:00:00Z
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
  upstream:
    repo: google/ax
    base_commit: f0228f1
---

# Track 4: AX Central (`~/projects/ax-central`)

## Hypothesis & Goal

Provide a native desktop control center (**Wails v2 + Go + Lit 3 WebComponents + `@xterm/xterm` + WebMCP**) to design, deploy, and inspect AX `Task`, `Workspace`, and `Model` resources across local and cluster environments, while transparently shimming `docker` and `docker buildx` to **Podman** for machines without Docker Desktop.[^upstream-ax][^upstream-substrate]

## External Project Structure (`~/projects/ax-central`)

- `wails.json` & `app.go` — Wails v2 native desktop shell, file dialogs, and atespace `TraySummary` grouping tasks by lifecycle phase.
- `shell.go` — Streaming command runner, interactive stdio terminal sessions, and container runtime detection (`docker` vs. `podman`).
- `docker-shim.sh` — Embedded `docker` → `podman` shim for `kind`, Agent Substrate, and AX build scripts (skips TLS on `localhost`/`127.0.0.1` Kind registries, preserves pushed manifest digests across Podman layer recompression, and emulates `docker buildx build --push` / `imagetools inspect`).
- `frontend/src/model/` — TypeScript state stores for clusters (`clusters.ts`), declarative YAML task design (`designer.ts`), and live AX resources (`resources.ts`).

## Verification & Build Commands (in `~/projects/ax-central`)

```bash
cd ~/projects/ax-central
make test           # go vet + go test -race + frontend Vitest (headless Chromium)
make lint           # gofmt, go vet, tsc --noEmit, prettier --check
make build          # npm run build + go build -o ax-central .
make dev            # wails dev live-reload session
```

## Related Experiment Tracks

- Connects to local stacks managed by [Track 1: Local Apple Container Substrate (ate-local)](/ate-local.md) or Podman/Kind clusters.
- Designs and launches workloads exercised in [Track 2a: Multi-Agent Swarm Recipes (01–08)](/swarm.md) and [Track 2b: Declarative Genkit Go Runner (genkit-runner)](/genkit.md).
- Complements the swarm execution trace replayer in [Track 3: Swarm Telemetry, Correlation IDs & Visual Replay](/viz.md).

[^upstream-ax]: google/ax: Agent Executor
[^upstream-substrate]: agent-substrate/substrate: Agent Substrate
