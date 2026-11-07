# Declarative Genkit Go Runner on AX (`genkit-runner`)

> **OKF v0.2 Track Metadata & Lineage**: [`okf/genkit.md`](../okf/genkit.md) · **Bundle Index**: [`okf/index.md`](../okf/index.md)

This experiment folder contains the manifests, automation scripts, and end-to-end tutorial for **`cmd/runners/genkit-runner`** ([`google/ax#538`](https://github.com/google/ax/issues/538)), which turns a declarative `Task.spec.config` [Dotprompt](https://genkit.dev/docs/go/dotprompt/) configuration and `Workspace` into a multi-protocol **A2A gRPC (`lf.a2a.v1.A2AService`) + A2A JSON-RPC + Genkit HTTP** agent server with durable session snapshots across `ax suspend` and `ax resume`.

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
