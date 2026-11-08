---
type: External Experiment
title: "Track 5: AX Images — Multi-Arch Task Image Repository (ghcr.io/ghchinoy/ax-images)"
description: "Standalone multi-arch (linux/amd64 + linux/arm64) AX task image repository publishing swarm-agent, genkit-runner, dgem-agent, and agy-agent with hard-linked /usr/local/bin/ax-task-runner -> /usr/local/bin/ax-agent and digest-pinned release manifests."
status: stable
tags: [ax-images, ghcr, multi-arch, swarm-agent, genkit-runner, dgem-agent, agy-agent, external]
generated:
  by: human:ghchinoy
  at: 2026-11-08T00:00:00Z
verified:
  - by: human:ghchinoy
    at: 2026-11-08T00:00:00Z
sources:
  - id: ghchinoy-ax-images
    resource: https://github.com/ghchinoy/ax-images
    title: "ghchinoy/ax-images: Multi-arch task images for AX"
  - id: rakyll-ax-images-pr-2
    resource: https://github.com/rakyll/ax-images/pull/2
    title: "rakyll/ax-images#2: hard-link ax-task-runner to ax-agent so host bind-mounts preserve agent binary"
  - id: upstream-ax
    resource: https://github.com/google/ax
    title: "google/ax: Agent Executor"
experiment:
  track: ax-images
  location: external
  local_path: ~/projects/ax-images
  beads:
    - ax-experiments-632
  entrypoints:
    - Makefile
    - internal/taskrunner/taskrunner.go
    - internal/agent/tools.go
    - images/swarm-agent/Dockerfile
    - images/genkit-runner/Dockerfile
    - images/dgem-agent/Dockerfile
    - images/agy-agent/Dockerfile
  upstream:
    repo: google/ax
    base_commit: f0228f1
    issues: [526, 538]
---

# Track 5: AX Images (`~/projects/ax-images`)

## Hypothesis & Goal

Provide a standalone, multi-arch (`linux/amd64` + `linux/arm64`), digest-pinned container image repository ([`ghchinoy/ax-images`](https://github.com/ghchinoy/ax-images) publishing to `ghcr.io/ghchinoy/ax-images/<name>`) for the custom agent runners exercised across `ax-experiments` and `ax-central`, while keeping [`rakyll/ax-images`](https://github.com/rakyll/ax-images) strictly for upstream issues and fixes.[^ghchinoy-ax-images][^rakyll-ax-images-pr-2][^upstream-ax]

Every image installs its entrypoint at `/usr/local/bin/ax-agent` with `/usr/local/bin/ax-task-runner` **hard-linked** (`ln -f`) to it, preventing host bind-mounts over `/usr/local/bin/ax-task-runner` from clobbering `/usr/local/bin/ax-agent`.[^rakyll-ax-images-pr-2]

## Published Images (`ghcr.io/ghchinoy/ax-images/*`)

- `swarm-agent` (`images/swarm-agent/`, `cmd/swarm-agent/`) — Multi-agent Gemini worker (`python:3.12-slim` + `google-genai` + `pyyaml` + `jq`) reading `Task.spec.config` via loopback metadata (`127.0.0.1:8099`) for [Track 2a: Multi-Agent Swarm Recipes (01–08)](/swarm.md).
- `genkit-runner` (`images/genkit-runner/`, `cmd/genkit-runner/`) — Declarative **Genkit Go** (`v1.14.0`) Dotprompt runner serving A2A gRPC (`lf.a2a.v1.A2AService`), A2A JSON-RPC, and Genkit HTTP on `:80` for [Track 2b: Declarative Genkit Go Runner (genkit-runner)](/genkit.md).
- `dgem-agent` (`images/dgem-agent/`, `cmd/dgem-agent/`) — **DiffusionGemma (`dgem`)** System-1 decision router (`dgem-router`) and `.json.tmpl` policy templates (`specialist_router.json.tmpl`, `support_triage.json.tmpl`, `agent_step_drift.json.tmpl`) for [Track 2c: System-1 Decision Routing & Guardrails with dgem + Genkit on AX (dgem)](/dgem.md).
- `agy-agent` (`images/agy-agent/`, `cmd/agy-agent/`, `internal/agent/`) — Dual-mode **Google Antigravity (`agy`)** coding agent (`antigravity-preview-09-2026` Gemini Interactions API + CLI/SDK): runs as a non-`dgem` baseline by default (matching `ghcr.io/rakyll/ax-images/antigravity`), or enables the 4-stage cascading `dgem` `PreToolUse` safety gate (`dgem_gate.py`, `tool_safety_gate.json.tmpl`) and `ax ssh` HITL approval when `spec.config.safetyGate: true` or `DGEM_GATEWAY_URL` is set, for [Track 2d: Antigravity (agy) Coding Agents on AX with Cascading dgem Safety Gates (agy)](/agy.md).

## Verification & Build Commands (in `~/projects/ax-images`)

```bash
cd ~/projects/ax-images
make test           # go vet ./... && go test ./...
make binaries       # cross-compile linux/amd64 or linux/arm64 static Go binaries
make apple-local    # build all 4 linux/arm64 images into macOS Apple container
make images         # build and push images to $(IMAGE_REPO) and record .digest files
make pin            # pin @sha256: digests into images/*/task.yaml and README.md
```

## Related Experiment Tracks

- Runs directly on [Track 1: Local Apple Container Substrate (ate-local)](/ate-local.md) and [Track 1b: Local Chromebook / Crostini Kind + Agent Substrate Stack (crostini)](/crostini.md).
- Packages the runtime images for [Track 2a: Multi-Agent Swarm Recipes (01–08)](/swarm.md), [Track 2b: Declarative Genkit Go Runner (genkit-runner)](/genkit.md), [Track 2c: System-1 Decision Routing & Guardrails with dgem + Genkit on AX (dgem)](/dgem.md), and [Track 2d: Antigravity (agy) Coding Agents on AX with Cascading dgem Safety Gates (agy)](/agy.md).
- Integrated into the Configurable Image Artifact Registry Catalog in [Track 4: AX Central — Desktop Control Plane, Task Designer & Podman Shim](/ax-central.md).

[^ghchinoy-ax-images]: ghchinoy/ax-images: Multi-arch task images for AX
[^rakyll-ax-images-pr-2]: rakyll/ax-images#2: hard-link ax-task-runner to ax-agent so host bind-mounts preserve agent binary
[^upstream-ax]: google/ax: Agent Executor
