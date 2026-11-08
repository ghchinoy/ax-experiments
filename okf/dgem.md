---
type: Experiment Track
title: "Track 2c: System-1 Decision Routing & Guardrails with dgem + Genkit on AX (dgem)"
description: "Discrete-diffusion System-1 decision policies (DiffusionGemma 26B-A4B) + Genkit Go v1.14.0 inside Apple container microVMs via ate-local: systemonex tool-interrupt guardrails, Streamable HTTP MCP triage, and a 1-to-3 Hesitation-gated scale-to-zero specialist router swarm."
status: stable
tags: [dgem, diffusiongemma, genkit, systemone, mcp, a2a, atelocal, swarm, router, hesitation]
generated:
  by: human:ghchinoy
  at: 2026-11-07T00:00:00Z
verified:
  - by: human:ghchinoy
    at: 2026-11-07T00:00:00Z
sources:
  - id: dgem-repo
    resource: https://github.com/GoogleCloudPlatform/dgem
    title: "GoogleCloudPlatform/dgem: DiffusionGemma as a Zero-Shot Decision Model"
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
  track: dgem
  location: in-tree
  folder: dgem/
  beads:
    - ax-experiments-c0h.8
  entrypoints:
    - dgem/ensure-stack.sh
    - dgem/01-tool-approval-microvm.sh
    - dgem/02-mcp-triage-agent.sh
    - dgem/03-specialist-router.sh
  upstream:
    repo: google/ax
    base_commit: 241bc4d
    issues: [538, 526]
  forks:
    - repo: ghchinoy/ax
      branch: feat/genkit-runner
    - repo: ghchinoy/ax
      branch: feat/ate-local-apple-container
---

# Track 2c: System-1 Decision Routing & Guardrails with `dgem` + Genkit on AX (`dgem`)

## Hypothesis & Goal

Prove that **[`dgem` (DiffusionGemma `26B-A4B-it`)](https://github.com/GoogleCloudPlatform/dgem)** running on Apple Silicon Metal (`:8080` + `:8095` gateway) can serve as a single-pass **System-1 Decision & Guardrail Engine** for **Genkit Go `v1.14.0`** agents running inside isolated **Apple `container`** microVMs (`192.168.64.x`) on AX:[^dgem-repo][^ax-issue-538]

1. **Configurable Endpoint Abstraction (`dgemgenkit.EndpointConfig`)**: Genkit `systemonex.SystemOne` clients switch seamlessly between local Metal, the Apple `container` host bridge (`DGEM_GATEWAY_URL=http://192.168.64.1:8095`), and remote Cloud Run / Vertex AI endpoints.
2. **Hesitation-Gated Tool-Approval Interrupts (`01-tool-approval-microvm.sh`)**: Inside an Apple `container` microVM, Genkit `v1.14.0`'s `middleware.ToolApprovalInterrupted` calls `dgem` (`calibration/agent_step_drift.json.tmpl`) to block prompt-injected tool calls (`drift="hijacked"`, `99.1%` confidence, `4.1%` hesitation) while resuming legitimate tools.
3. **Zero-Code Declarative `genkit-runner` + `dgem` MCP (`02-mcp-triage-agent.sh`)**: A declarative `Task.spec.config` agent connects `Workspace.spec.mcp` to `http://192.168.64.1:8095/mcp`, auto-discovers all 7 `dgem` MCP tools, and executes policy decisions over A2A JSON-RPC.
4. **1-to-3 Hesitation-Gated Scale-to-Zero Specialist Router (`03-specialist-router.sh`)**: A `dgem-router` microVM evaluates `specialist_router.json.tmpl` in one forward pass (~2.6s warm KV cache) and uses normalized Shannon entropy (**Hesitation %**, $H / \ln K$) to wake **only 1** `Suspended` specialist microVM (`specialist-billing`, `specialist-security`, `specialist-engineering`) when Hesitation `< 16%` (`Clear`), or fan out to the **top-2** specialists when Hesitation `>= 16%` (`Unsure`, demonstrated at `18.6%` on a cross-domain billing + code bug query), suspending specialists back to 0 CPU / 0 MB RAM after each turn.[^fork-atelocal]

## Repository Artifacts (`dgem/`)

- `dgem/README.md` — Track overview, quickstart, and recipe catalog.
- `dgem/GUIDE.md` — Host $\leftrightarrow$ `vmnet` bridge architecture (`192.168.64.1:8095`), `dgemgenkit.EndpointConfig` reference, and empirical scoreboard across all 3 recipes.
- `dgem/templates/specialist_router.json.tmpl` — 4-slot single-pass routing policy (`specialist`, `cross_domain`, `urgent`, `severity`).
- `dgem/router/main.go` — Standalone Genkit Go `v1.14.0` + `systemonex.SystemOne` router CLI.
- `dgem/manifests/workspaces.yaml` & `dgem/manifests/tasks.yaml` — Declarative AX `Workspace` and `Task` manifests for the router and 3 scale-to-zero specialist agents.
- `dgem/01-tool-approval-microvm.sh`, `dgem/02-mcp-triage-agent.sh`, `dgem/03-specialist-router.sh` — Runnable end-to-end verification scripts.
- `viz/traces/09-dgem-specialist-router.jsonl` — Recorded execution trace for replay in `viz/web`.

## Related Experiment Tracks

- Builds on [Track 1: Local Apple Container Substrate (ate-local)](/ate-local.md) for microVM lifecycle (`ax resume` / `ax suspend`) and `vmnet` networking.
- Extends [Track 2b: Declarative Genkit Go Runner (genkit-runner)](/genkit.md) and [Track 2a: Multi-Agent Swarm Recipes (01–08)](/swarm.md) with System-1 diffusion routing and hesitation-gated fan-out.
- Emits replayable JSONL traces for [Track 3: Swarm Telemetry, Correlation IDs & Visual Replay](/viz.md) and powers the 4-stage `PreToolUse` safety gate in [Track 2d: Antigravity (agy) Coding Agents on AX with Cascading dgem Safety Gates (agy)](/agy.md).

[^dgem-repo]: GoogleCloudPlatform/dgem: DiffusionGemma as a Zero-Shot Decision Model
[^ax-issue-538]: google/ax#538: Genkit Go runner
[^fork-atelocal]: ghchinoy/ax:feat/ate-local-apple-container
