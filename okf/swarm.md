---
type: Experiment Track
title: "Track 2a: Multi-Agent Swarm Recipes (01–08)"
description: "Eight runnable multi-agent swarm and sandbox boundary recipes (swarm/01..08) on Apple container microVMs."
status: stable
tags: [swarm, multi-agent, gemini, apple-container, workspace, metadata]
generated:
  by: human:ghchinoy
  at: 2026-10-31T00:00:00Z
verified:
  - by: human:ghchinoy
    at: 2026-10-31T00:00:00Z
sources:
  - id: ax-issue-479
    resource: https://github.com/google/ax/issues/479
    title: "google/ax#479: Loopback metadata boundary (127.0.0.1:8099)"
  - id: ax-issue-496
    resource: https://github.com/google/ax/issues/496
    title: "google/ax#496: Single workspace binding per Task"
  - id: ax-issue-523
    resource: https://github.com/google/ax/issues/523
    title: "google/ax#523: Declarative Task.spec.config (google.protobuf.Struct)"
experiment:
  track: swarm
  location: in-tree
  folder: swarm/
  beads:
    - ax-experiments-c0h
    - ax-experiments-c0h.1
    - ax-experiments-c0h.2
  entrypoints:
    - swarm/01-hello-swarm.sh
    - swarm/02-repo-inspector.sh
    - swarm/03-seed-matrix.sh
    - swarm/04-review-panel.sh
    - swarm/05-debate.sh
    - swarm/06-map-reduce.sh
    - swarm/07-suspend-resume.sh
    - swarm/08-spec-config-metadata.sh
  upstream:
    repo: google/ax
    base_commit: f0228f1
    issues: [479, 496, 519, 523]
  forks:
    - repo: ghchinoy/ax
      branch: feat/ate-local-apple-container
---

# Track 2a: Multi-Agent Swarm Recipes (`01`–`08`)

## Hypothesis & Goal

Stress-test AX beyond single-task execution across parallel microVM fan-out, Workspace git clones (`#496`), stochastic parameter sweeps, specialized Gemini code review panels, multi-turn adversarial debates, scatter-gather map-reduce synthesis, `/workspace` volume persistence across `ax suspend` / `ax resume`, and declarative `Task.spec.config` (`#523`) + loopback metadata (`127.0.0.1:8099`, `#479`).[^ax-issue-479][^ax-issue-496][^ax-issue-523]

## Repository Artifacts (`swarm/`)

- `swarm/README.md` — Recipe catalog (`01`–`08`) and quickstart.
- `swarm/GUIDE.md` — Developer guide covering the three swarm orchestration patterns and empirical timings.
- `swarm/lib.sh` — Shared orchestration and opt-in trace emission library.
- `swarm/agent-image/` — Local `linux/arm64` Gemini agent image (`ax-agent-local:latest`).
- `swarm/01..08-*.sh` — Standalone executable swarm recipes.

## Related Experiment Tracks

- Executes on top of [Track 1: Local Apple Container Substrate (ate-local)](/ate-local.md).
- Complements declarative single-binary agent execution in [Track 2b: Declarative Genkit Go Runner (genkit-runner)](/genkit.md).
- Emits `.jsonl` execution traces recorded and replayed by [Track 3: Swarm Telemetry, Correlation IDs & Visual Replay](/viz.md).

[^ax-issue-479]: google/ax#479: Loopback metadata boundary (127.0.0.1:8099)
[^ax-issue-496]: google/ax#496: Single workspace binding per Task
[^ax-issue-523]: google/ax#523: Declarative Task.spec.config (google.protobuf.Struct)
