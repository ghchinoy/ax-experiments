# System-1 Decision Routing & Guardrails with `dgem` + Genkit Go on AX (`dgem`)

> **Open Knowledge Format (OKF) v0.2 Track Metadata & Lineage**: [`okf/dgem.md`](../okf/dgem.md) · **Bundle Index**: [`okf/index.md`](../okf/index.md)

This experiment track combines **[`dgem` (DiffusionGemma `26B-A4B-it`)](https://github.com/GoogleCloudPlatform/dgem)**, **[Genkit Go `v1.14.0`](https://github.com/firebase/genkit)** (`plugins/systemone/exp`, `plugins/middleware`, `plugins/mcp`), and **[AX (`ate-local`)](../ate-local/README.md)** to run **System-1 discrete-diffusion decision policies** and **Hesitation-gated scale-to-zero specialist routing** inside macOS **Apple `container`** microVMs (`192.168.64.x`).

---

## Contents of This Folder

| File / Directory | Purpose |
|---|---|
| [`GUIDE.md`](./GUIDE.md) | Cold-start setup & teardown guide, `vmnet` host-bridge topology (`192.168.64.1:8095`), `dgemgenkit.EndpointConfig` reference, empirical results across all 3 recipes, alternatives considered, and operational constraints. |
| [`ensure-stack.sh`](./ensure-stack.sh) | Pre-flight verification and stack lifecycle helper (`./dgem/ensure-stack.sh {up\|status\|down\|image}`). Automatically sourced by Recipes `01`–`03` so each script can run from a cold terminal. |
| [`01-tool-approval-microvm.sh`](./01-tool-approval-microvm.sh) | **Recipe 01** (`make dgem-01`): Cross-compiles `genkit-tool-approval` and `genkit-bulk-synth` (`linux/arm64`) into `dgem-genkit-task:latest` and runs them inside an Apple `container` microVM via `DGEM_GATEWAY_URL=http://192.168.64.1:8095`. |
| [`02-mcp-triage-agent.sh`](./02-mcp-triage-agent.sh) | **Recipe 02** (`make dgem-02`): Launches a declarative `genkit-runner` ([`google/ax#538`](https://github.com/google/ax/issues/538), [`../genkit/`](../genkit/README.md)) microVM connected to `dgem`'s Streamable HTTP MCP server (`http://192.168.64.1:8095/mcp`), auto-discovering all 7 `dgem` tools and triaging an inbox ticket over [Agent2Agent (A2A)](https://github.com/a2aproject/A2A) JSON-RPC. |
| [`03-specialist-router.sh`](./03-specialist-router.sh) | **Recipe 03** (`make dgem-03`): **1-to-3 Scale-to-Zero Specialist Router Swarm** — 1 `dgem-router` microVM classifies incoming queries across 3 `Suspended` specialist Genkit agents (`specialist-billing`, `specialist-security`, `specialist-engineering`), waking 1 specialist when `Hesitation < 16%`, `cross_domain=no`, and runner-up probability `< 0.20`, or waking and querying the top-2 specialists in parallel when `Hesitation >= 16%`, `cross_domain=yes`, or runner-up probability `>= 0.20`. |
| [`templates/specialist_router.json.tmpl`](./templates/specialist_router.json.tmpl) | 4-slot single-pass routing policy (`specialist` 3-way choice, `cross_domain` boolean, `urgent` boolean, `severity` 4-level score). |
| [`router/`](./router/README.md) | Standalone Go router CLI (`dgem-router`, [`router/main.go`](./router/main.go)) using `dgemgenkit.EndpointConfig` and Genkit's `systemonex.SystemOne` plugin inside the router microVM. |
| [`manifests/workspaces.yaml`](./manifests/workspaces.yaml) & [`manifests/tasks.yaml`](./manifests/tasks.yaml) | Declarative AX `Workspace` and `Task` manifests for `dgem-router` and the 3 specialist agents. |

---

## Prerequisites

1. **Apple Silicon Mac** (32 GB+ unified memory recommended) with **Apple `container`** CLI (`/usr/local/bin/container`) and **Go 1.26+**.
2. **Sibling `~/projects/dgem` checkout** (or set `DGEM_REPO=/path/to/dgem`) with `diffgemma` and the 4-bit model pack (`model/diffgemma-26b-a4b-it-q4/model.dgq.bin`, ~18.84 GiB) installed:
   ```bash
   git clone https://github.com/GoogleCloudPlatform/dgem.git ~/projects/dgem
   cd ~/projects/dgem && make setup && make download && make build
   ```
3. **Sibling `~/projects/ax` checkout** on the `feat/ate-local-apple-container` branch (with `origin/feat/genkit-runner` fetched for Recipes 02 and 03).
4. **`GEMINI_API_KEY`** exported in your shell *(required for Recipes 02 and 03, which run Gemini-backed `genkit-runner` specialist agents; not required for Recipe 01)*.

---

## Quickstart (One-Command Cold Start & Teardown)

Every recipe script (`01`–`03`) sources [`ensure-stack.sh`](./ensure-stack.sh), which automatically checks and starts `container system start`, background `diffgemma` (`:8080`), background `dgem serve` (`0.0.0.0:8095` with `DGEM_ALLOWED_HOSTS=192.168.64.1`), `ax-agent-local:latest`, and `ate-local` + `ax-server` (`:8090`).

From `~/projects/ax-experiments`:

```bash
cd ~/projects/ax-experiments

# Optional: bring up and inspect both local stacks explicitly
make dgem-up
make dgem-status

# Recipe 01: systemonex.SystemOne + ToolApproval interrupt guardrail + bulk KV-cache evaluation (no GEMINI_API_KEY needed)
make dgem-01

# Recipes 02 & 03 require GEMINI_API_KEY for the genkit-runner agents:
export GEMINI_API_KEY="your-key"

# Recipe 02: Declarative genkit-runner + dgem Streamable HTTP MCP over A2A JSON-RPC
make dgem-02

# Recipe 03: 1-to-3 Hesitation-gated scale-to-zero specialist router swarm
make dgem-03

# Stop both the AX stack (:8090) and dgem/diffgemma stack (:8095/:8080) when finished:
make dgem-down
```

### Demo Mode: Temporary Cloud Run GPU (~200 ms Decisions vs. 3–8 s Local Metal)

To record a fast demo without running the 19.5 GiB local Metal `diffgemma` engine on your laptop, deploy a temporary Cloud Run GPU service (`dgemma`) in `~/projects/dgem`, pass `DGEM_CLOUDRUN_URL` to `make dgem-up` / `make dgem-03` (which points the local `:8095` gateway at Cloud Run with `--gcp-auth` and `DGEM_BACKEND=cloudrun`), and tear down the Cloud Run GPU immediately afterward:

```bash
# 1. Deploy temporary Cloud Run GPU service (in ~/projects/dgem)
GCP_PROJECT=<PROJECT> ALLOW_GROUP=<USER_OR_GROUP_EMAIL> make -C ~/projects/dgem cloudrun-deploy
export DGEM_CLOUDRUN_URL="$(gcloud run services describe dgemma --region=us-central1 --format='value(status.url)')/v1"

# 2. Restart the local :8095 gateway backed by Cloud Run GPU (skips local diffgemma :8080) and run the demo
cd ~/projects/ax-experiments
make dgem-down
DGEM_CLOUDRUN_URL="${DGEM_CLOUDRUN_URL}" make dgem-up
GEMINI_API_KEY="your-key" DGEM_CLOUDRUN_URL="${DGEM_CLOUDRUN_URL}" make dgem-03

# 3. Tear down the Cloud Run GPU service immediately after recording to eliminate idle GPU cost
make -C ~/projects/dgem cloudrun-teardown
```

See [`GUIDE.md`](./GUIDE.md) for the full architectural walkthrough, empirical measurements, alternatives considered, and operational constraints.
