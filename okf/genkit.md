---
type: Experiment Track
title: "Track 2b: Declarative Genkit Go Runner (genkit-runner)"
description: "Declarative Dotprompt agents on AX with A2A gRPC, A2A JSON-RPC, Genkit HTTP, MCP, skills, and suspend/resume session snapshots (google/ax#538)."
status: stable
tags: [genkit, runner, dotprompt, a2a, a2a-grpc, mcp, skills, atelocal, gce, crostini]
generated:
  by: human:ghchinoy
  at: 2026-10-31T00:00:00Z
verified:
  - by: human:ghchinoy
    at: 2026-10-31T00:00:00Z
sources:
  - id: ax-issue-538
    resource: https://github.com/google/ax/issues/538
    title: "google/ax#538: Genkit Go runner"
  - id: ax-issue-526
    resource: https://github.com/google/ax/issues/526
    title: "google/ax#526: ax local start/status/stop"
  - id: genkit-pr-6988
    resource: https://github.com/firebase/genkit/pull/6988
    title: "firebase/genkit#6988: Register MCP tools in GetActiveTools(ctx, g)"
  - id: fork-genkit-runner
    resource: https://github.com/ghchinoy/ax/tree/feat/genkit-runner
    title: "ghchinoy/ax:feat/genkit-runner"
  - id: fork-atelocal
    resource: https://github.com/ghchinoy/ax/tree/feat/ate-local-apple-container
    title: "ghchinoy/ax:feat/ate-local-apple-container"
experiment:
  track: genkit
  location: in-tree
  folder: genkit/
  beads:
    - ax-experiments-c0h.3
    - ax-experiments-c0h.4
    - ax-experiments-c0h.5
    - ax-experiments-c0h.6
    - ax-experiments-c0h.7
  entrypoints:
    - genkit/run-apple-container.sh
    - genkit/bootstrap-gce.sh
    - genkit/workspace.yaml
    - genkit/task.yaml
    - genkit/task-apple-container.yaml
  upstream:
    repo: google/ax
    base_commit: 241bc4d
    issues: [538, 526, 523]
  forks:
    - repo: ghchinoy/ax
      branch: feat/genkit-runner
    - repo: ghchinoy/ax
      branch: feat/ate-local-apple-container
---

# Track 2b: Declarative Genkit Go Runner (`genkit-runner`)

## Hypothesis & Goal

Prove that a single static Go binary (`cmd/runners/genkit-runner`, `google/ax#538`) embedding AX's `runner` package and Genkit Go (`v1.14.0`) can turn a declarative `Task.spec.config` Dotprompt manifest + `Workspace` (inline files, `.agents/skills/*/SKILL.md`, and `Workspace.spec.mcp` stdio/HTTP servers) into a multi-protocol **A2A gRPC (`lf.a2a.v1.A2AService`) + A2A JSON-RPC + Genkit HTTP** agent server whose multi-turn session state (`/workspace/.genkit/snapshots`) survives across `ax suspend` and `ax resume`.[^ax-issue-538][^fork-genkit-runner]

## Repository Artifacts (`genkit/`)

- `genkit/README.md` — Track overview, manifest catalog, and Apple container quickstart.
- `genkit/TUTORIAL.md` — Three-part tutorial covering (1) local Linux/Crostini execution, (2) GCE Ubuntu 24.04 Kind + Agent Substrate v0.6.0 wake-on-request E2E, and (3) macOS Apple `container` microVM verification.
- `genkit/workspace.yaml` — Sample `Workspace` with `retry_test.go`, `incident-runbook/SKILL.md`, and `tools/incident_mcp.py`.
- `genkit/task-apple-container.yaml` & `genkit/run-apple-container.sh` — Automated 6-step microVM verification on macOS.
- `genkit/task.yaml` & `genkit/bootstrap-gce.sh` — GCE Ubuntu 24.04 Kind + Substrate v0.6.0 E2E bootstrap.

## Related Experiment Tracks

- Runs locally inside Apple `container` microVMs via [Track 1: Local Apple Container Substrate (ate-local)](/ate-local.md) and inside gVisor sandboxes on ChromeOS via [Track 1b: Local Chromebook / Crostini Kind + Agent Substrate Stack (crostini)](/crostini.md).
- Extends the `Task.spec.config` and workspace boundaries tested in [Track 2a: Multi-Agent Swarm Recipes (01–08)](/swarm.md).

[^ax-issue-538]: google/ax#538: Genkit Go runner
[^fork-genkit-runner]: ghchinoy/ax:feat/genkit-runner
