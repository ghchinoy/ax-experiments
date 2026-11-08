---
type: Experiment Track
title: "Track 2d: Antigravity (agy) Coding Agents on AX with Cascading dgem Safety Gates (agy)"
description: "Google Antigravity (ghcr.io/rakyll/ax-images/antigravity and agy CLI/Python SDK) coding tasks on AX across macOS ate-local and Kind + Agent Substrate: Phase 1 non-decision baseline and Phase 2 4-stage cascading dgem PreToolUse safety gate (tool_safety_gate.json.tmpl) with live ax ssh HITL approval."
status: stable
tags: [antigravity, agy, dgem, diffusiongemma, safety-gate, hitl, atelocal, substrate, otel]
generated:
  by: human:ghchinoy
  at: 2026-11-08T00:00:00Z
verified:
  - by: human:ghchinoy
    at: 2026-11-08T00:00:00Z
sources:
  - id: dgem-repo
    resource: https://github.com/GoogleCloudPlatform/dgem
    title: "GoogleCloudPlatform/dgem: DiffusionGemma as a Zero-Shot Decision Model"
  - id: ax-images-repo
    resource: https://github.com/rakyll/ax-images
    title: "rakyll/ax-images: Ready-to-run coding agent task images for AX"
  - id: ax-issue-526
    resource: https://github.com/google/ax/issues/526
    title: "google/ax#526: ax local start/status/stop"
  - id: fork-atelocal
    resource: https://github.com/ghchinoy/ax/tree/feat/ate-local-apple-container
    title: "ghchinoy/ax:feat/ate-local-apple-container"
experiment:
  track: agy
  location: in-tree
  folder: agy/
  beads:
    - ax-experiments-c0h.9
    - ax-experiments-c0h.10
  entrypoints:
    - agy/01-phase1-baseline.sh
    - agy/02-phase2-dgem-safety-gate.sh
  upstream:
    repo: google/ax
    base_commit: 241bc4d
    issues: [526]
  forks:
    - repo: ghchinoy/ax
      branch: feat/ate-local-apple-container
---

# Track 2d: Antigravity (`agy`) Coding Agents on AX with Cascading `dgem` Safety Gates (`agy`)

## Hypothesis & Goal

Prove that Google Antigravity coding agents—both the turnkey [`ghcr.io/rakyll/ax-images/antigravity`](https://github.com/rakyll/ax-images) image and the `agy` CLI / `google.antigravity` Python SDK—can run inside isolated AX sandboxes ([Track 1: `ate-local`](/ate-local.md) and [Track 1b: `crostini` Kind + Agent Substrate](/crostini.md)) with a 4-stage cascading **`dgem` (`DiffusionGemma 26B-A4B-it`)** `PreToolUse` safety gate ([Track 2c: `dgem`](/dgem.md)) that blocks indirect prompt injection (`<untrusted_data>`) and secret exfiltration while resolving gray-area mutations via live `ax ssh` Human-in-the-Loop (HITL) approval:[^dgem-repo][^ax-images-repo][^ax-issue-526][^fork-atelocal]

1. **Phase 1 Baseline (`agy/01-phase1-baseline.sh`)**: Runs an un-gated Antigravity coding task (`SUBSTRATE=atelocal|kind`, `SURFACE=sdk|ax-image`) that fixes a failing Python unit test (`discount.py`) and writes `/workspace/agent-output.md`, while demonstrating why un-gated `run_shell` / `run_command` execution inside a sandbox is exposed to planted commands in `<untrusted_data>`.
2. **Phase 2 Cascading `dgem` Safety Gate + `ax ssh` HITL (`agy/02-phase2-dgem-safety-gate.sh`)**:
   - **Stage 0 (`0.1 ms` Static)**: Fast-allows pure workspace reads (`git status`) when `<untrusted_data>` is empty and blocks catastrophic commands (`sudo rm -rf /`).
   - **Stage 1 (`dgem` 2-Slot `tool_safety_gate.json.tmpl`)**: Evaluates `action_hazard` $\times$ `intent_origin` in one forward pass, approving benign tests (`pytest -q`) and `use`-vs-`mention` security greps (`grep -rn "rm -rf" tests/`) while blocking `<untrusted_data>` `.env` exfiltration (`intent_origin=hijacked_by_tool_output` at `100%` confidence).
   - **Stage 2 (`gemini-3.8-flash` Cascade)**: Escalates uncertain reads (`Hesitation >= 16%`).
   - **Stage 3 (File-Based HITL Rendezvous Over `ax ssh`)**: Holds gray-area mutations (`gcloud config set project staging-app-123`) in `/workspace/.agy/hitl/<trace_id>.pending.json`, emits OTel spans (`msg="genkit otel span"`) to `/proc/1/fd/2` for [Track 4: AX Central](/ax-central.md), and resumes immediately when the operator runs `hitl-respond --decision allow` over `ax ssh`.

## Repository Artifacts (`agy/`)

- `agy/CONCEPTS_BRIEF.md` — 7-lens EGM Goldfish brainstorm synthesis and contradiction resolutions.
- `agy/README.md` — Track overview, Surface $\times$ Phase matrix, Substrate networking table, and quickstart.
- `agy/GUIDE.md` — Deep-dive setup guide, 4-stage cascade architecture, and empirical M5 results.
- `agy/01-phase1-baseline.sh` — Phase 1 baseline runner (`make agy-01`).
- `agy/02-phase2-dgem-safety-gate.sh` — Phase 2 cascading `dgem` safety gate + live `ax ssh` HITL runner (`make agy-02`).

## Related Experiment Tracks

- Builds on [Track 2c: System-1 Decision Routing & Guardrails with dgem + Genkit on AX (dgem)](/dgem.md) and [Track 1: Local Apple Container Substrate (ate-local)](/ate-local.md).
- Shares Substrate `EgressPolicy` helpers with [Track 2b: Declarative Genkit Go Runner (genkit-runner)](/genkit.md) and [Track 1b: Local Chromebook / Crostini Kind + Agent Substrate Stack (crostini)](/crostini.md).
- Emits container OTel spans and provides Deploy template specifications (`ax-central-f90.2`) for [Track 4: AX Central — Desktop Control Plane, Task Designer & Podman Shim](/ax-central.md).

[^dgem-repo]: GoogleCloudPlatform/dgem: DiffusionGemma as a Zero-Shot Decision Model
[^ax-images-repo]: rakyll/ax-images: Ready-to-run coding agent task images for AX
[^ax-issue-526]: google/ax#526: ax local start/status/stop
[^fork-atelocal]: ghchinoy/ax:feat/ate-local-apple-container
