# AX Experiments: Multi-Agent Swarms, Declarative Runners, Telemetry & Local Substrate

> **OKF v0.2 Knowledge Bundle**: [`okf/index.md`](./okf/index.md) · **Agent Contract**: [`AGENTS.md`](./AGENTS.md)

Companion R&D repository for prototyping, stress-testing, and visualizing **[AX (Agent Executor)](https://github.com/google/ax)** and **[Agent Substrate](https://github.com/agent-substrate/substrate)**—from 3-second local microVMs on Apple Silicon macOS (`ate-local`) to declarative **Genkit Go** agents (`genkit-runner`), multi-agent swarm topologies, and interactive execution trace replay.

---

## Why This Repository Exists

While [`google/ax`](https://github.com/google/ax) and [`go.ate.dev/substrate`](https://github.com/agent-substrate/substrate) provide the core runtime and actor control plane, this repository serves as the **experimental proving ground** where new developer workflows, multi-agent coordination patterns, and telemetry RFCs are validated before graduating upstream.

Each experiment track is organized either in its own self-contained top-level directory or in an external companion project (`~/projects/*`), and indexed with **Open Knowledge Format (OKF) v0.2** provenance metadata in [`okf/index.md`](./okf/index.md):

| Track | Location | Focus & Hypothesis | Upstream / Fork Alignment & Docs |
|---|---|---|---|
| **1. Local macOS Substrate (`ate-local`)** | [`ate-local/`](./ate-local/README.md) | Run the full AX control plane + `ateapipb.ControlServer` on Apple Silicon using native macOS **Apple `container`** microVMs (`192.168.64.x` `vmnet` bridge) and PostgreSQL—zero Kubernetes, `kind`, or Docker Desktop required. | [`google/ax#526`](https://github.com/google/ax/issues/526), [`ghchinoy/ax:feat/ate-local-apple-container`](https://github.com/ghchinoy/ax/tree/feat/ate-local-apple-container) · [`PROPOSAL.md`](./ate-local/PROPOSAL.md) · [`TESTING.md`](./ate-local/TESTING.md) · [`okf/ate-local.md`](./okf/ate-local.md) |
| **1b. Chromebook / Crostini Kind + Substrate (`crostini`)** | [`crostini/`](./crostini/README.md) | Run the full upstream AX control plane + Agent Substrate (`v1.0.0-rc.1`) with real gVisor (`runsc`) sandboxes, `atenet-router`, and RustFS snapshots locally on a ChromeOS Linux (Crostini / Bagels KVM) VM running Debian 13 (`trixie`). | [`google/ax#553`](https://github.com/google/ax/pull/553) · [`crostini/README.md`](./crostini/README.md) · [`crostini/GUIDE.md`](./crostini/GUIDE.md) · [`okf/crostini.md`](./okf/crostini.md) |
| **2a. Multi-Agent Swarms (`01`–`08`)** | [`swarm/`](./swarm/README.md) | Stress-test parallel microVM fan-out, Workspace git clones, stochastic parameter sweeps, Gemini code review panels, adversarial red-team debates, map-reduce synthesis, volume persistence across `suspend`/`resume`, and `Task.spec.config` loopback metadata (`127.0.0.1:8099`). | [`#479`](https://github.com/google/ax/issues/479), [`#496`](https://github.com/google/ax/issues/496), [`#523`](https://github.com/google/ax/issues/523) · [`swarm/README.md`](./swarm/README.md) · [`swarm/GUIDE.md`](./swarm/GUIDE.md) · [`okf/swarm.md`](./okf/swarm.md) |
| **2b. Declarative Genkit Go Runner** | [`genkit/`](./genkit/README.md) | Turn a declarative `Task.spec.config` Dotprompt manifest + `Workspace` (files, `SKILL.md`, stdio MCP servers) into a dual-protocol A2A + Genkit HTTP agent server that preserves multi-turn sessions across `ax suspend` and `ax resume`. | [`google/ax#538`](https://github.com/google/ax/issues/538), [`ghchinoy/ax:feat/genkit-runner`](https://github.com/ghchinoy/ax/tree/feat/genkit-runner) · [`genkit/README.md`](./genkit/README.md) · [`genkit/TUTORIAL.md`](./genkit/TUTORIAL.md) · [`okf/genkit.md`](./okf/genkit.md) |
| **3. Swarm Telemetry & Visual Replay** | [`viz/`](./viz/README.md) | Expose observability gaps in multi-agent runs (control-plane blind spots during `ax ssh`, flat task storage without `parent_task_id`/`correlation_id`, missing W3C `traceparent`) and prototype a JSONL trace schema, Go recorder (`ax-trace`), and Lit 3 + Force-Graph + Cytoscape CoSE replay UI. | [`viz/README.md`](./viz/README.md) · [`viz/SCHEMA.md`](./viz/SCHEMA.md) · [`viz/FRICTION-REPORT.md`](./viz/FRICTION-REPORT.md) · [`okf/viz.md`](./okf/viz.md) |
| **4. AX Central (External Desktop App)** | `~/projects/ax-central` *(external)* | Standalone **Wails v2 + Go + Lit 3 + `@xterm/xterm` + WebMCP** desktop app for designing, deploying, and inspecting AX `Task`/`Workspace`/`Model` resources, managing clusters, and shimming `docker`-to-`podman` (`docker-shim.sh` with `buildx` digest preservation). | [`okf/ax-central.md`](./okf/ax-central.md) · `bd show ax-experiments-bxv` |

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

To run the swarm recipes (`swarm/01..08`), the Genkit microVM runner (`genkit/run-apple-container.sh`), and record live traces on your Mac:

1. **Prerequisites**:
   - **Apple Silicon Mac** running macOS 26+
   - **Apple `container` CLI** 1.0+ (`/usr/local/bin/container` — verify with `container system start && container list`)
   - **Go 1.26+**
   - **`GEMINI_API_KEY`** exported in your shell *(only required for AI swarm recipes `04`, `05`, `06` and `genkit/run-apple-container.sh`)*

2. **Start the local AX stack** from [`ghchinoy/ax`](https://github.com/ghchinoy/ax) (`feat/ate-local-apple-container` branch):
   ```bash
   git clone -b feat/ate-local-apple-container https://github.com/ghchinoy/ax.git ~/projects/ax
   cd ~/projects/ax-experiments
   make stack-up
   ```
   *(Or directly inside `~/projects/ax`: `make local-up && source .ax-local/env`)*. This launches `postgres:17-alpine` in an Apple container, starts `ate-local` on `:50051`, and starts `ax-server` on `:8090` in ~3 seconds.

3. **Build the local arm64 Gemini agent image** *(needed for recipes `02`, `04`, `05`, `06`, `08`, and `genkit/run-apple-container.sh`)*:
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

To test declarative Dotprompt agents with workspace tools, skills (`SKILL.md`), stdio MCP servers, and suspend/resume session snapshots (on Apple `container` microVMs, local Linux/Crostini, or a GCE Ubuntu 24.04 VM with Kind + Agent Substrate v0.6.0):

```bash
export GEMINI_API_KEY="your-key"
./genkit/run-apple-container.sh
```

See [`/genkit/README.md`](/genkit/README.md) and the 3-part [`/genkit/TUTORIAL.md`](/genkit/TUTORIAL.md) for full details.

### 4. Record & Replay Swarm Execution Traces (`viz/`)

Capture a live `.jsonl` trace (conforming to [`/viz/SCHEMA.md`](/viz/SCHEMA.md)) while running any swarm recipe:

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

Before committing changes to markdown concepts, scripts, the trace recorder, or the visualizer, run `make check` (or the individual checks below using [`ghchinoy/binder`](https://github.com/ghchinoy/binder) and [`ghchinoy/okf-proto`](https://github.com/ghchinoy/okf-proto)):

```bash
# Run all static checks (OKF v0.2 validation, shell lint, Go recorder build/vet)
make check

# 1. Validate OKF v0.2 bundle conformance, concept graph & Protobuf export
binder validate okf --strict
binder review okf --strict --require-tier human-reviewed
okf-proto export okf --format json >/dev/null

# 2. Lint swarm and genkit shell scripts
bash -n swarm/*.sh genkit/*.sh

# 3. Build and vet the Go trace recorder
cd viz/recorder && go build ./... && go vet ./...

# 4. Typecheck and build the Lit 3 + Vite web visualizer
cd viz/web && pnpm typecheck && pnpm build
```

---

## Repository Structure

```
ax-experiments/
├── README.md               # Repository overview, quickstart & verification gates
├── AGENTS.md               # Agent contract, OKF ruleset & Beads (bd) tracking rules
├── Makefile                # Convenience targets for images, swarm recipes, recorder & web UI
├── okf/                    # OKF v0.2 Knowledge Bundle (provenance, trust & upstream/fork lineage)
│   ├── index.md            # Root OKF v0.2 bundle index (declares okf_version: "0.2")
│   ├── ate-local.md        # Track 1 concept card & lineage
│   ├── crostini.md         # Track 1b Chromebook / Crostini Kind + Substrate concept card
│   ├── swarm.md            # Track 2a concept card & lineage
│   ├── genkit.md           # Track 2b concept card & lineage
│   ├── viz.md              # Track 3 concept card & lineage
│   └── ax-central.md       # Track 4 external project concept card (~/projects/ax-central)
├── ate-local/              # Track 1: Local Apple Container Substrate (google/ax#526)
│   ├── README.md           # Track overview & quick verification
│   ├── PROPOSAL.md         # Architecture proposal & Apple Silicon benchmarks
│   ├── TESTING.md          # Automated unit/live microVM test suite & stack walkthrough
│   └── archive/            # Archived early proposal and glidepath drafts
├── crostini/               # Track 1b: Local Chromebook / Crostini Kind + Agent Substrate Stack
│   ├── README.md           # Track overview & quickstart
│   ├── GUIDE.md            # Step-by-step Debian 13 (trixie) guide, gotchas & empirical benchmarks
│   └── setup-crostini.sh   # Idempotent Crostini prerequisite installer & cluster setup script
├── swarm/                  # Track 2a: Multi-Agent Swarm Recipes (01–08)
│   ├── README.md           # Recipe catalog & quickstart
│   ├── GUIDE.md            # Developer guide, 3 swarm patterns & empirical timings
│   ├── agent-image/        # arm64 Gemini agent image (reads Task.spec.config via loopback metadata)
│   ├── lib.sh              # Shared orchestration & opt-in trace emission library
│   └── 01..08-*.sh         # Fan-out, git workspaces, code review panel, debate, map-reduce, spec.config
├── genkit/                 # Track 2b: Declarative Genkit Go Runner (google/ax#538)
│   ├── README.md           # Track overview & manifest catalog
│   ├── TUTORIAL.md         # 3-part tutorial (local Linux, GCE Kind + Substrate, Apple container)
│   ├── workspace.yaml      # Workspace with files, incident-runbook SKILL.md, and stdio MCP server
│   ├── task.yaml           # Vertex AI / Linux & GCE Task manifest
│   ├── task-apple-container.yaml # Apple container microVM Task manifest
│   ├── run-apple-container.sh    # Automated Apple container E2E script
│   └── bootstrap-gce.sh    # Ubuntu 24.04 GCE startup script (Kind + Substrate v0.6.0 + AX + Genkit)
└── viz/                    # Track 3: Interactive Swarm Trace Recorder & Web Visualizer
    ├── README.md           # Visualizer & recorder quickstart
    ├── SCHEMA.md           # JSONL trace event schema
    ├── FRICTION-REPORT.md  # Correlation IDs, swarm lineage & W3C TraceContext RFC
    ├── recorder/           # Go trace recorder (ax-trace)
    ├── traces/             # Recorded swarm execution traces (.jsonl)
    └── web/                # Lit 3 + Force-Graph + Cytoscape CoSE replay UI (Auto/Light/Dark mode)
```

---

## Experiment Tracking & Contributing

This repository uses **[Beads (`bd`)](https://github.com/steveyegge/beads)** and the **Open Knowledge Format (OKF) v0.2** bundle in [`okf/`](./okf/index.md) to track research epics, runnable experiment spikes, and architectural decisions. Experiments may be purely repo-local or linked to `0..N` fork branches and upstream [`google/ax`](https://github.com/google/ax) / [`go.ate.dev/substrate`](https://github.com/agent-substrate/substrate) issues/PRs:

```bash
bd list --all          # View all research tracks (Epics 1–3) and experiment beads
bd ready               # Show unblocked experiments ready to run
```

When contributing a new experiment or swarm recipe:
1. Place the experiment in its track folder (or a new self-contained top-level folder) with a clean `README.md`, add or update its OKF v0.2 concept card in [`okf/`](./okf/index.md), and register the experiment in `bd` (see [`AGENTS.md`](./AGENTS.md)).
2. Run the experiment against an isolated local stack and record measured timings with `bd update <id> --notes="..."`.
3. Open a pull request or upstream the validated change directly to [`google/ax`](https://github.com/google/ax) or [`agent-substrate/substrate`](https://github.com/agent-substrate/substrate).
