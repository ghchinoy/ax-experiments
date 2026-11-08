# Declarative Genkit Go Runner on AX (`genkit-runner`)

> **OKF v0.2 Track Metadata & Lineage**: [`okf/genkit.md`](../okf/genkit.md) · **Bundle Index**: [`okf/index.md`](../okf/index.md)

This experiment folder contains the manifests, multi-agent A2A gRPC examples, automation scripts, and end-to-end tutorial for **`cmd/runners/genkit-runner`** ([`google/ax#538`](https://github.com/google/ax/issues/538)), which turns a declarative `Task.spec.config` [Dotprompt](https://genkit.dev/docs/go/dotprompt/) configuration and `Workspace` into a multi-protocol **A2A gRPC (`lf.a2a.v1.A2AService`) + A2A JSON-RPC + Genkit HTTP** agent server with durable session snapshots across `ax suspend` and `ax resume`.

---

## Contents of This Folder

| File | Purpose |
|---|---|
| [`CONCEPTS_BRIEF.md`](./CONCEPTS_BRIEF.md) | **EGM Concepts Brief**: Architecture and 7-lens Goldfish review synthesis for the Sandboxed EGM Review Panel and Autonomous In-Cluster A2A Delegation examples. |
| [`01-egm-review-panel.sh`](./01-egm-review-panel.sh) | **Example 01 — Sandboxed Elephant-Goldfish Design & Review Loop (`1m 10.9s`)**: 1 stateful Elephant task + 3 parallel stateless Goldfish tasks (`goldfish-design`, `goldfish-catalyst`, `goldfish-comprehension`) mounting skills from `~/projects/elephant-goldfish-model/agents/*.md`, streaming structured JSON (`output.schema`) over **A2A gRPC (`SendStreamingMessage`)**, and exercising residency inversion (`ax suspend` / wake-on-request). |
| [`02-in-cluster-delegation.sh`](./02-in-cluster-delegation.sh) | **Example 02 — Autonomous In-Cluster Agent-to-Agent Delegation (`45.1s`)**: `lead-engineer` invokes an in-sandbox stdio MCP server (`/usr/local/bin/a2a-mcp-bridge`) that dials `atenet-router.ate-system.svc.cluster.local:443` over mTLS using A2A gRPC from *inside* the gVisor sandbox, waking a suspended `security-specialist` task on demand without a host relay. |
| [`cmd/a2a-mcp-bridge/main.go`](./cmd/a2a-mcp-bridge/main.go) | Static Go stdio MCP server exposing `delegate_to_actor(actor, prompt, context_id)` over in-cluster `atenet-router:443` mTLS + A2A gRPC, logging telemetry to `/workspace/.genkit/mcp-delegation.jsonl`. |
| [`cmd/egm-orchestrator/main.go`](./cmd/egm-orchestrator/main.go) | Shared Go driver for `--mode=egm-panel` (Example 01) and `--mode=in-cluster-delegation` (Example 02). |
| [`internal/axclient/client.go`](./internal/axclient/client.go) | Shared Go package for Substrate `EgressPolicy` provisioning, `atenet-router` mTLS loading, and A2A gRPC (`SendMessage` / `SendStreamingMessage`) client calls. |
| [`TUTORIAL.md`](/genkit/TUTORIAL.md) | Three-part tutorial: (1) local Linux/Crostini runner mode, (2) GCE Ubuntu 24.04 Kind + Agent Substrate wake-on-request E2E, and (3) macOS Apple `container` microVM E2E via `ate-local`. |
| [`workspace.yaml`](./workspace.yaml) | Declarative `Workspace` materializing a sample Go service (`README.md`, buggy `retry_test.go`), `.agents/skills/incident-runbook/SKILL.md`, and a zero-dependency Python stdio MCP server (`tools/incident_mcp.py`). |
| [`task-apple-container.yaml`](./task-apple-container.yaml) | Declarative `Task` manifest for running `genkit-runner` inside an Apple `container` microVM on macOS via [`/ate-local/README.md`](/ate-local/README.md). |
| [`run-apple-container.sh`](./run-apple-container.sh) | Automated 6-step macOS Apple `container` microVM test exercising A2A Agent Card discovery, MCP tool invocation, workspace file edits, `ax suspend` → `ax resume` microVM cold-boot, and multi-turn session snapshot recovery. |
| [`task.yaml`](./task.yaml) | Declarative `Task` manifest using `vertexai/gemini-2.5-flash` (ADC) for local Linux/Crostini or GCE cluster runs. |
| [`bootstrap-gce.sh`](./bootstrap-gce.sh) | Self-contained Ubuntu 24.04 LTS GCE startup script that installs Docker, Kind, Agent Substrate, AX, and the `genkit-runner` image. |

---

## Quickstart: Multi-Agent Examples on Kind + Agent Substrate (Crostini / Linux)

With a local Kind + Agent Substrate (`v1.0.0-rc.1`) + AX cluster running (see [`/crostini/GUIDE.md`](/crostini/GUIDE.md)):

```bash
cd ~/projects/ax-experiments

# Example 01: 1 Stateful Elephant + 3 Parallel Stateless Goldfish Reviewers over A2A gRPC
./genkit/01-egm-review-panel.sh

# Example 02: Autonomous In-Sandbox MCP -> A2A gRPC Delegation over atenet-router:443 mTLS
./genkit/02-in-cluster-delegation.sh
```

---

## Quickstart: macOS Apple Container MicroVM (`ate-local`)

With the local stack running from [`/ate-local/README.md`](/ate-local/README.md) and `ax-agent-local:latest` built (`make agent-image`):

```bash
export GEMINI_API_KEY="your-key"
./genkit/run-apple-container.sh
```

See [`CONCEPTS_BRIEF.md`](./CONCEPTS_BRIEF.md) and [`TUTORIAL.md`](/genkit/TUTORIAL.md) for the full architecture and verified outputs.
