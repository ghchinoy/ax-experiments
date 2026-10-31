# AX Experiments: Multi-Agent Swarms, Telemetry & Local Substrate on macOS

Companion repository for exploring, stress-testing, and visualizing **[AX (Agent Executor)](https://github.com/google/ax)** and **[Agent Substrate](https://github.com/agent-substrate/substrate)** on Apple Silicon macOS using native **Apple `container`** microVMs (`ate-local`).

---

## Repository Structure

```
ax-experiments/
├── swarm/                  # 8 runnable multi-agent swarm & sandbox recipes (01–08)
│   ├── agent-image/        # arm64 Gemini agent image (reads Task.spec.config via loopback metadata)
│   ├── lib.sh              # Shared orchestration & opt-in trace emission library
│   └── 01..08-*.sh         # Fan-out, git workspaces, code review panel, debate, map-reduce, spec.config
├── viz/                    # Interactive Swarm Trace Recorder & Web Visualizer
│   ├── SCHEMA.md           # JSONL trace event schema
│   ├── recorder/           # Go trace recorder (ax-trace)
│   ├── traces/             # Recorded swarm execution traces (.jsonl)
│   └── web/                # Lit 3 + Force-Graph + Cytoscape CoSE replay UI (Auto/Light/Dark mode)
└── docs/                   # Proposals, testing guides, and architecture RFCs
    ├── INTRO-ax-on-apple-container.md
    ├── TESTING-ate-local.md
    ├── PROPOSAL-apple-container-substrate.md
    └── FRICTION-REPORT-correlation-and-swarm-telemetry.md
```

---

## Quickstart

### 1. Start the Local AX + `ate-local` Stack
In your `~/projects/ax` checkout (on the `feat/ate-local-apple-container` branch):

```bash
cd ~/projects/ax
make local-up
source .ax-local/env
```

This starts `postgres:17-alpine` in an Apple container, `ate-local` (`go.ate.dev/substrate/pkg/proto/ateapipb.ControlServer`) on `:50051`, and `ax-server` on `:8090`.

### 2. Run Swarm Recipes
```bash
cd ~/projects/ax-experiments

# Build the local arm64 Gemini agent image (needed for recipes 02, 04, 05, 06)
make agent-image

# Run non-LLM recipes (no API key needed)
./swarm/01-hello-swarm.sh
./swarm/07-suspend-resume.sh
./swarm/08-spec-config-metadata.sh

# Run Gemini multi-agent swarm recipes (requires GEMINI_API_KEY)
export GEMINI_API_KEY="your-key"
./swarm/04-review-panel.sh
./swarm/05-debate.sh
./swarm/06-map-reduce.sh
```

### 3. Launch the Interactive Swarm Visualizer
```bash
make viz-preview
```
Open the local URL to replay recorded swarm traces with Force-Graph particle streams or Cytoscape CoSE layouts.
