# AX Experiments: Multi-Agent Swarms, Declarative Runners, Telemetry & Local Substrate

Companion R&D repository for prototyping, stress-testing, and visualizing **[AX (Agent Executor)](https://github.com/google/ax)** and **[Agent Substrate](https://github.com/agent-substrate/substrate)**—from 3-second local microVMs on Apple Silicon macOS (`ate-local`) to declarative **Genkit Go** agents (`genkit-runner`), multi-agent swarm topologies, and interactive execution trace replay.

---

## Why This Repository Exists

While [`google/ax`](https://github.com/google/ax) and [`go.ate.dev/substrate`](https://github.com/agent-substrate/substrate) provide the core runtime and actor control plane, this repository serves as the **experimental proving ground** where new developer workflows, multi-agent coordination patterns, and telemetry RFCs are validated before graduating upstream:

| Track | Directory | Focus & Hypothesis | Upstream Alignment & Specs |
|---|---|---|---|
| **1. Local macOS Substrate (`ate-local`)** | [`docs/`](./docs/) | Run the full AX control plane + `ateapipb.ControlServer` on Apple Silicon using native macOS **Apple `container`** microVMs (`192.168.64.x` `vmnet` bridge) and PostgreSQL—zero Kubernetes, `kind`, or Docker Desktop required. | [`google/ax#526`](https://github.com/google/ax/issues/526), [`ghchinoy/ax:feat/ate-local-apple-container`](https://github.com/ghchinoy/ax/tree/feat/ate-local-apple-container) · [Proposal](./docs/PROPOSAL-apple-container-substrate.md) · [Testing Guide](./docs/TESTING-ate-local.md) |
| **2. Multi-Agent Swarms (`01`–`08`)** | [`swarm/`](./swarm/) | Stress-test parallel microVM fan-out, Workspace git clones, stochastic parameter sweeps, Gemini code review panels, adversarial red-team debates, map-reduce synthesis, volume persistence across `suspend`/`resume`, and `Task.spec.config` loopback metadata (`127.0.0.1:8099`). | [`#479`](https://github.com/google/ax/issues/479), [`#496`](https://github.com/google/ax/issues/496), [`#523`](https://github.com/google/ax/issues/523) · [Developer Intro](./docs/INTRO-ax-on-apple-container.md) · [`swarm/README.md`](./swarm/README.md) |
| **3. Declarative Genkit Go Runner** | [`genkit/`](./genkit/) | Turn a declarative `Task.spec.config` Dotprompt manifest + `Workspace` (files, `SKILL.md`, stdio MCP servers) into a dual-protocol A2A + Genkit HTTP agent server that preserves multi-turn sessions across `ax suspend` and `ax resume`. | [`google/ax#538`](https://github.com/google/ax/issues/538), `ghchinoy/ax:feat/genkit-runner` · [Genkit Runner Tutorial](./docs/TUTORIAL-genkit-runner.md) |
| **4. Swarm Telemetry & Visual Replay** | [`viz/`](./viz/) | Expose observability gaps in multi-agent runs (control-plane blind spots during `ax ssh`, flat task storage without `parent_task_id`/`correlation_id`, missing W3C `traceparent`) and prototype a JSONL trace schema, Go recorder (`ax-trace`), and Lit 3 + Force-Graph + Cytoscape CoSE replay UI. | [Friction Report & Telemetry RFC](./docs/FRICTION-REPORT-correlation-and-swarm-telemetry.md) · [`viz/SCHEMA.md`](./viz/SCHEMA.md) · [`viz/README.md`](./viz/README.md) |

---

## System Topology

```
   ax CLI (localhost:8090)
     │  gRPC (ax.io/v1alpha1)
     ▼
   ax-server (:8090) ──► PostgreSQL 17 (:5432, runs in Apple container)
     │
     │  gRPC (ateapipb.ControlServer)                ┌──────────────────────────────┐
     ▼                                               │  viz/recorder (ax-trace)     │
   ate-local (:50051)                                │  Captures server logs +      │
     │  /usr/local/bin/container                     │  recipe events (.jsonl)      │
     ▼                                               └──────────────┬───────────────┘
   Apple Container microVMs (vmnet: 192.168.64.x)                   │
     ├── :80    /healthz, /readyz, guest.ProcessService (ax ssh)    ▼
     ├── :8099  Loopback metadata (/metadata/v1alpha1/ax/*)   viz/web (Lit 3 UI)
     └── PID 1  ax-task-runner or genkit-runner               Force-Graph & Cytoscape
```

---

## Installation & Prerequisites

### Option A: Explore the Swarm Visualizer Immediately (No AX Stack Required)

If you want to inspect recorded multi-agent swarm traces right away in your browser, you only need **Node.js 20+** and **`pnpm`**:

```bash
git clone https://github.com/ghchinoy/ax-experiments.git
cd ax-experiments
make viz-install
make viz-dev
```

Open the local URL shown by Vite (`http://localhost:5173`) to scrub through pre-recorded traces (`01-hello-swarm`, `04-review-panel`, `05-debate`, `06-map-reduce`) in **Force-Graph** or **Cytoscape CoSE** mode.

### Option B: Full Local AX + `ate-local` Stack on macOS

To run the swarm recipes (`swarm/01..08`) and record live traces on your Mac:

1. **Prerequisites**:
   - **Apple Silicon Mac** running macOS 26+
   - **Apple `container` CLI** 1.0+ (`/usr/local/bin/container` — verify with `container system start && container list`)
   - **Go 1.26+**
   - **`GEMINI_API_KEY`** exported in your shell *(only required for AI recipes `04`, `05`, and `06`)*

2. **Start the local AX stack** from the [`ghchinoy/ax`](https://github.com/ghchinoy/ax) checkout (`feat/ate-local-apple-container` branch):
   ```bash
   git clone -b feat/ate-local-apple-container https://github.com/ghchinoy/ax.git ~/projects/ax
   cd ~/projects/ax
   make local-up
   source .ax-local/env
   ```
   This launches `postgres:17-alpine` in an Apple container, starts `ate-local` on `:50051`, and starts `ax-server` on `:8090` in ~3 seconds.

3. **Build the local arm64 Gemini agent image** *(needed for recipes `02`, `04`, `05`, `06`)*:
   ```bash
   cd ~/projects/ax-experiments
   make agent-image
   ```

---

## Usage

### 1. Run a Multi-Agent Swarm Recipe

Run the 8-node parallel microVM fan-out recipe (no API key required):

```bash
make swarm-01
```

Expected output (~8–9 seconds on Apple Silicon):

```text
==> [01 Hello Swarm] Spawning 8 parallel tasks on Apple Container...
--> Applying and resuming 8 tasks...
--> Waiting for all 8 microVMs to report Ready on vmnet...

TASK NAME          WORKER IP        HOSTNAME                 OS / ARCH
---------          ---------        --------                 ---------
hello-node-0       192.168.64.81    ate-default-hello-node-0 Linux aarch64
hello-node-1       192.168.64.80    ate-default-hello-node-1 Linux aarch64
...
hello-node-7       192.168.64.75    ate-default-hello-node-7 Linux aarch64

==> Swarm completed in 9s (provisioned and ready in 8s).
```

### 2. Swarm Recipe Catalog (`swarm/`)

All 8 recipes can be run via `make swarm-XX` or directly via `./swarm/XX-*.sh` and automatically clean up their tasks on exit:

| Recipe | Make Target | Needs `GEMINI_API_KEY`? | What It Demonstrates |
|---|---|:---:|---|
| [`01-hello-swarm.sh`](./swarm/01-hello-swarm.sh) | `make swarm-01` | No | 8 parallel microVMs, dynamic `vmnet` IP allocation (`192.168.64.x`), host fan-out. |
| [`02-repo-inspector.sh`](./swarm/02-repo-inspector.sh) | `make swarm-02` | No | Single-workspace binding (`#496`), parallel git repository clones into `/workspace`. |
| [`03-seed-matrix.sh`](./swarm/03-seed-matrix.sh) | `make swarm-03` | No | 6-node stochastic parameter sweep / fuzz matrix across isolated sandboxes. |
| [`04-review-panel.sh`](./swarm/04-review-panel.sh) | `make swarm-04` | **Yes** | 3 specialized Gemini reviewers (Security Auditor, Go Readability, Performance). |
| [`05-debate.sh`](./swarm/05-debate.sh) | `make swarm-05` | **Yes** | Multi-turn adversarial debate (Proposer vs. SRE Critic) across separate microVMs. |
| [`06-map-reduce.sh`](./swarm/06-map-reduce.sh) | `make swarm-06` | **Yes** | Scatter-gather: 3 parallel Mapper agents + 1 Reducer synthesis agent. |
| [`07-suspend-resume.sh`](./swarm/07-suspend-resume.sh) | `make swarm-07` | No | Proves `/workspace` volume state survives `ax suspend` → `ax resume` while RAM resets. |
| [`08-spec-config-metadata.sh`](./swarm/08-spec-config-metadata.sh) | `make swarm-08` | No | Exercises `Task.spec.config` (`#523`), inlined Workspace files, and loopback metadata (`127.0.0.1:8099`, `#479`). |

### 3. Run the Declarative Genkit Go Runner (`genkit/`)

To test declarative Dotprompt agents with workspace tools, skills (`SKILL.md`), stdio MCP servers, and suspend/resume session snapshots (either locally or on a GCE Ubuntu 24.04 VM with Kind + Agent Substrate v0.6.0), follow the step-by-step guide in [`docs/TUTORIAL-genkit-runner.md`](./docs/TUTORIAL-genkit-runner.md) using the manifests in [`genkit/`](./genkit/).

### 4. Record & Replay Swarm Execution Traces (`viz/`)

Capture a live `.jsonl` trace (conforming to [`viz/SCHEMA.md`](./viz/SCHEMA.md)) while running any swarm recipe:

```bash
# Build the Go trace recorder
make build-recorder

# Record recipe + control-plane events to a JSONL trace file
AX_TRACE_RECIPE=1 ./viz/recorder/ax-trace -out viz/traces/my-run.jsonl &
RECORDER_PID=$!
./swarm/05-debate.sh
kill $RECORDER_PID

# Build and preview the web visualizer
make viz-build
make viz-preview
```

---

## Local Development & Verification

### Running Against an Isolated AX Stack

When developing or testing new experiments alongside an existing local stack, always launch an isolated stack with dedicated ports and state directory:

```bash
AX_LOCAL_DIR=/private/var/folders/qs/4zfn7mrs7kq23y6rgjnd_zxc0000gn/T/opencode/ax-exp \
AX_LOCAL_POSTGRES_PORT=5441 \
AX_LOCAL_SUBSTRATE_PORT=50061 \
AX_LOCAL_SERVER_PORT=8096 \
AX_LOCAL_POSTGRES_NAME=ax-exp-postgres \
~/projects/ax/examples/ate_local/local-stack.sh up
```

### Verification Gates

Before committing changes to scripts, the trace recorder, or the visualizer, run the verification checks:

```bash
# 1. Lint swarm shell scripts
bash -n swarm/*.sh

# 2. Build and vet the Go trace recorder
cd viz/recorder && go build ./... && go vet ./...

# 3. Typecheck and build the Lit 3 + Vite web visualizer
cd viz/web && pnpm typecheck && pnpm build
```

---

## Repository Structure & Documentation

```
ax-experiments/
├── AGENTS.md               # Agent contract & Beads (bd) experiment tracking rules
├── Makefile                # Convenience targets for images, swarm recipes, recorder & web UI
├── genkit/                 # Genkit Go runner (google/ax#538) manifests & GCE E2E bootstrap
│   ├── workspace.yaml      # Workspace with files, incident-runbook SKILL.md, and stdio MCP server
│   ├── task.yaml           # Declarative Dotprompt Task using vertexai/gemini-2.5-flash
│   └── bootstrap-gce.sh    # Ubuntu 24.04 GCE startup script (Kind + Substrate v0.6.0 + AX + Genkit)
├── swarm/                  # 8 runnable multi-agent swarm & sandbox recipes (01–08)
│   ├── agent-image/        # arm64 Gemini agent image (reads Task.spec.config via loopback metadata)
│   ├── lib.sh              # Shared orchestration & opt-in trace emission library
│   └── 01..08-*.sh         # Fan-out, git workspaces, code review panel, debate, map-reduce, spec.config
├── viz/                    # Interactive Swarm Trace Recorder & Web Visualizer
│   ├── SCHEMA.md           # JSONL trace event schema
│   ├── recorder/           # Go trace recorder (ax-trace)
│   ├── traces/             # Recorded swarm execution traces (.jsonl)
│   └── web/                # Lit 3 + Force-Graph + Cytoscape CoSE replay UI (Auto/Light/Dark mode)
└── docs/                   # Proposals, testing guides, tutorials, and architecture RFCs
```

### Architecture Guides & Proposals (`docs/`)

- **[`TUTORIAL-genkit-runner.md`](./docs/TUTORIAL-genkit-runner.md)** — Two-part tutorial for declarative, suspendable Genkit Go agents on AX (local Crostini/Linux runner mode + full GCE Kind/Substrate cluster E2E with `atenet-router` scale-to-zero wakeup).
- **[`INTRO-ax-on-apple-container.md`](./docs/INTRO-ax-on-apple-container.md)** — Developer guide introducing AX primitives on Apple `container`, the three swarm orchestration patterns, and empirical timings for recipes `01`–`08`.
- **[`PROPOSAL-apple-container-substrate.md`](./docs/PROPOSAL-apple-container-substrate.md)** — Architectural proposal and benchmark analysis for `ate-local` (`ateapipb.ControlServer` on macOS Apple `container`).
- **[`TESTING-ate-local.md`](./docs/TESTING-ate-local.md)** — Step-by-step verification guide for running automated unit/live tests and exercising the full local stack.
- **[`FRICTION-REPORT-correlation-and-swarm-telemetry.md`](./docs/FRICTION-REPORT-correlation-and-swarm-telemetry.md)** — Post-implementation RFC proposing `correlation_id`, `parent_task`, W3C `TraceContext` injection, and AX-mediated inter-actor messaging.

---

## Experiment Tracking & Contributing

This repository uses **[Beads (`bd`)](https://github.com/steveyegge/beads)** to track research epics, runnable experiment spikes, and architectural decisions against upstream [`google/ax`](https://github.com/google/ax) and [`go.ate.dev/substrate`](https://github.com/agent-substrate/substrate):

```bash
bd list --all          # View all research tracks (Epics 1–3) and experiment beads
bd ready               # Show unblocked experiments ready to run
```

When contributing a new experiment or swarm recipe:
1. Register the experiment bead with `bd create` linking the target `ax` branch, upstream issue/PR, and `docs/` spec (see [`AGENTS.md`](./AGENTS.md) for required metadata flags).
2. Run the experiment against an isolated local stack and record measured timings with `bd update <id> --notes="..."`.
3. Open a pull request or upstream the validated change directly to [`google/ax`](https://github.com/google/ax) or [`agent-substrate/substrate`](https://github.com/agent-substrate/substrate).
