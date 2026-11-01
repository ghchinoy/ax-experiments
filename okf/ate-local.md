---
type: Experiment Track
title: "Track 1: Local Apple Container Substrate (ate-local)"
description: "Native macOS Local Substrate (ateapipb.ControlServer) backed by Apple container microVMs and PostgreSQL (google/ax#526)."
status: stable
tags: [atelocal, apple-container, substrate, macos, microvm, postgres]
generated:
  by: human:ghchinoy
  at: 2026-10-31T00:00:00Z
verified:
  - by: human:ghchinoy
    at: 2026-10-31T00:00:00Z
sources:
  - id: ax-issue-526
    resource: https://github.com/google/ax/issues/526
    title: "google/ax#526: ax local start/status/stop"
  - id: ax-pr-504
    resource: https://github.com/google/ax/pull/504
    title: "google/ax#504: In-process local runtime spike (superseded by #526)"
  - id: fork-atelocal
    resource: https://github.com/ghchinoy/ax/tree/feat/ate-local-apple-container
    title: "ghchinoy/ax:feat/ate-local-apple-container"
  - id: upstream-substrate
    resource: https://github.com/agent-substrate/substrate
    title: "agent-substrate/substrate: Agent Substrate v0.6.0 Control API"
experiment:
  track: ate-local
  location: in-tree
  folder: ate-local/
  beads:
    - ax-experiments-1rx
    - ax-experiments-1rx.1
    - ax-experiments-1rx.2
    - ax-experiments-1rx.3
  entrypoints:
    - ate-local/README.md
    - ate-local/PROPOSAL.md
    - ate-local/TESTING.md
  upstream:
    repo: google/ax
    base_commit: f0228f1
    issues: [526, 515, 517, 532, 536]
    prs: [504]
  forks:
    - repo: ghchinoy/ax
      branch: feat/ate-local-apple-container
---

# Track 1: Local Apple Container Substrate (`ate-local`)

## Hypothesis & Goal

Implement the **Agent Substrate Control gRPC API** (`go.ate.dev/substrate/pkg/proto/ateapipb.ControlServer` v0.6.0) backed by macOS's native **Apple `container`** runtime (`/usr/local/bin/container`), enabling the unmodified `ax` CLI and `ax-server` (with PostgreSQL 17) to provision, resume, suspend, and `ax ssh` into isolated Linux microVMs (`192.168.64.x` `vmnet` bridge) in ~3.3 seconds—without Kubernetes (`kind`), Docker Desktop, gVisor, or cloud infrastructure.[^ax-issue-526][^fork-atelocal]

## Repository Artifacts (`ate-local/`)

- `ate-local/README.md` — Track overview and quick verification commands.
- `ate-local/PROPOSAL.md` — Full architectural proposal, Substrate concept mapping, and empirical Apple Silicon benchmarks.
- `ate-local/TESTING.md` — Step-by-step verification suite (unit tests + live microVM tests + local stack walkthrough).
- `ate-local/archive/prior-proposal.md` & `ate-local/archive/glidepath.md` — Archived initial drafts.

## Empirical Outcomes

- **Stack Startup (`local-stack.sh up`)**: ~3.3s (`postgres:17-alpine` + `ate-local` `:50051` + `ax-server` `:8090`).
- **Actor Resume → Ready (`vmnet` IP assigned & `/readyz` 200 OK)**: 0.70s median.
- **Interactive Guest Exec (`ax ssh`)**: 0.03s over direct `vmnet` bridge IP (`192.168.64.x:80`).

## Related Experiment Tracks

- Provides the local microVM substrate for [Track 2a: Multi-Agent Swarm Recipes (01–08)](/swarm.md) and [Track 2b: Declarative Genkit Go Runner (genkit-runner)](/genkit.md).
- Emits control-plane lifecycle logs consumed by [Track 3: Swarm Telemetry, Correlation IDs & Visual Replay](/viz.md).

[^ax-issue-526]: google/ax#526: ax local start/status/stop
[^fork-atelocal]: ghchinoy/ax:feat/ate-local-apple-container
