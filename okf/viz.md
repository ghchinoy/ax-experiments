---
type: Experiment Track
title: "Track 3: Swarm Telemetry, Correlation IDs & Visual Replay"
description: "JSONL trace event schema, Go recorder (ax-trace), Lit 3 + Force-Graph + Cytoscape CoSE replay UI, and swarm lineage RFC."
status: stable
tags: [viz, telemetry, trace, force-graph, cytoscape, lit, rfc]
generated:
  by: human:ghchinoy
  at: 2026-10-31T00:00:00Z
verified:
  - by: human:ghchinoy
    at: 2026-10-31T00:00:00Z
sources:
  - id: ax-issue-346
    resource: https://github.com/google/ax/issues/346
    title: "google/ax#346: Task status lifecycle after command exit"
experiment:
  track: viz
  location: in-tree
  folder: viz/
  beads:
    - ax-experiments-311
    - ax-experiments-311.1
    - ax-experiments-311.2
  entrypoints:
    - viz/recorder/main.go
    - viz/web
  upstream:
    repo: google/ax
    base_commit: f0228f1
    issues: [346]
---

# Track 3: Swarm Telemetry, Correlation IDs & Visual Replay (`viz/`)

## Hypothesis & Goal

Expose the observability blind spots in AX when running multi-agent swarms (`ax ssh` bypassing the control plane, flat task storage without `parent_task_id` or `correlation_id`, missing W3C `TraceContext` propagation) and prototype a concrete JSONL trace schema, a Go trace recorder (`ax-trace`), and an interactive Lit 3 + Force-Graph + Cytoscape CoSE web replay application.[^ax-issue-346]

## Repository Artifacts (`viz/`)

- `viz/README.md` — Visualizer and trace recorder quickstart.
- `viz/SCHEMA.md` — JSON Lines (`.jsonl`) trace event specification.
- `viz/FRICTION-REPORT.md` — Architectural friction report and RFC proposing `correlation_id`, `parent_task`, W3C `TraceContext` injection, and AX-mediated inter-actor messaging.
- `viz/recorder/` — Go trace recorder (`ax-trace`).
- `viz/traces/` — Pre-recorded multi-agent swarm traces (`01`, `04`, `05`, `06`).
- `viz/web/` — Lit 3 + Vite + Force-Graph + Cytoscape CoSE replay UI (Auto/Light/Dark themes).

## Related Experiment Tracks

- Records and replays execution traces from [Track 2a: Multi-Agent Swarm Recipes (01–08)](/swarm.md) running on [Track 1: Local Apple Container Substrate (ate-local)](/ate-local.md).
- Complements the desktop control plane in [Track 4: AX Central — Desktop Control Plane, Task Designer & Podman Shim](/ax-central.md).

[^ax-issue-346]: google/ax#346: Task status lifecycle after command exit
