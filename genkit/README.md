---
type: Experiment Track
title: "Declarative Genkit Go Runner on AX (genkit-runner)"
description: "Overview, manifest catalog, and quickstart for running declarative Dotprompt agents with MCP, skills, A2A JSON-RPC, and durable session snapshots on Apple container microVMs or GCE Kind clusters."
status: stable
tags: [genkit, runner, dotprompt, a2a, mcp, skills, atelocal]
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
  - id: fork-genkit-runner
    resource: https://github.com/ghchinoy/ax/tree/feat/genkit-runner
    title: "ghchinoy/ax:feat/genkit-runner"
  - id: fork-atelocal
    resource: https://github.com/ghchinoy/ax/tree/feat/ate-local-apple-container
    title: "ghchinoy/ax:feat/ate-local-apple-container"
experiment:
  track: genkit
  beads:
    - ax-experiments-c0h.3
    - ax-experiments-c0h.4
    - ax-experiments-c0h.5
  entrypoints:
    - genkit/run-apple-container.sh
    - genkit/bootstrap-gce.sh
  upstream:
    repo: google/ax
    base_commit: f0228f1
    issues: [538, 526, 523]
  forks:
    - repo: ghchinoy/ax
      branch: feat/genkit-runner
    - repo: ghchinoy/ax
      branch: feat/ate-local-apple-container
---

# Declarative Genkit Go Runner on AX (`genkit-runner`)

This experiment folder contains the manifests, automation scripts, and end-to-end tutorial for **`cmd/runners/genkit-runner`** ([`google/ax#538`](https://github.com/google/ax/issues/538)), which turns a declarative `Task.spec.config` [Dotprompt](https://genkit.dev/docs/go/dotprompt/) configuration and `Workspace` into a dual-protocol **A2A JSON-RPC + Genkit HTTP** agent server with durable session snapshots across `ax suspend` and `ax resume`.

---

## Contents of This Folder

| File | Purpose |
|---|---|
| [`TUTORIAL.md`](/genkit/TUTORIAL.md) | Three-part tutorial: (1) local Linux/Crostini runner mode, (2) GCE Ubuntu 24.04 Kind + Agent Substrate v0.6.0 wake-on-request E2E, and (3) macOS Apple `container` microVM E2E via `ate-local`. |
| [`workspace.yaml`](./workspace.yaml) | Declarative `Workspace` materializing a sample Go service (`README.md`, buggy `retry_test.go`), `.agents/skills/incident-runbook/SKILL.md`, and a zero-dependency Python stdio MCP server (`tools/incident_mcp.py`). |
| [`task-apple-container.yaml`](./task-apple-container.yaml) | Declarative `Task` manifest for running `genkit-runner` inside an Apple `container` microVM on macOS via [`/ate-local/README.md`](/ate-local/README.md). |
| [`run-apple-container.sh`](./run-apple-container.sh) | Automated 6-step macOS Apple `container` microVM test exercising A2A Agent Card discovery, MCP tool invocation, workspace file edits, `ax suspend` → `ax resume` microVM cold-boot, and multi-turn session snapshot recovery. |
| [`task.yaml`](./task.yaml) | Declarative `Task` manifest using `vertexai/gemini-2.5-flash` (ADC) for local Linux/Crostini or GCE cluster runs. |
| [`bootstrap-gce.sh`](./bootstrap-gce.sh) | Self-contained Ubuntu 24.04 LTS GCE startup script that installs Docker, Kind, Agent Substrate v0.6.0, AX, and the `genkit-runner` image. |

---

## Quickstart (macOS Apple Container MicroVM)

With the local stack running from [`/ate-local/README.md`](/ate-local/README.md) and `ax-agent-local:latest` built (`make agent-image`):

```bash
export GEMINI_API_KEY="your-key"
./genkit/run-apple-container.sh
```

See [`TUTORIAL.md`](/genkit/TUTORIAL.md) for the full walkthrough and verified outputs across all three execution environments.
