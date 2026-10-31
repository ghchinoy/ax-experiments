# AX Swarm Visualizer

Interactive replay tool for multi-agent swarm execution traces on macOS with Apple container.

Built with **Vite 8**, **Lit 3**, **Force-Graph** (dynamic force-directed particle physics), and **Cytoscape.js** (structured CoSE layout).

---

## Quick Start

### 1. Build and Preview

```bash
cd ~/projects/tmp/ax/viz/web
pnpm install
pnpm build
pnpm preview
```

Open `http://localhost:4173` (or the port Vite outputs) in your browser.

### 2. Live Development

```bash
pnpm dev
```

---

## Features

- **Dual Visualization Modes**:
  - **Force Graph**: Physics simulation showing live actor node states and animated message particle streams (`kind: "msg"`).
  - **Cytoscape CoSE**: Deterministic hierarchical/organic layout with bezier/dashed edges.
- **Scrubbing & Playback**:
  - Variable speed playback (0.5x, 1x, 2x, 4x).
  - High-precision timeline scrubber to examine any millisecond of a swarm execution.
- **Synchronized Event Log**:
  - Live filterable event stream displaying timestamps, source subsystems (`ax`, `controller`, `recipe`), and step descriptions.
  - Click any event in the log to jump directly to that point in the replay.
- **Included Recorded Traces**:
  - `01. Hello Swarm` (8 microVM parallel fan-out).
  - `04. AI Code Review Panel` (3 parallel specialized Gemini reviewers).
  - `05. AI Red-Team Debate` (adversarial proposer & critic exchange).
  - `06. Map-Reduce Synthesis` (3 mappers + 1 reducer scatter-gather).

---

## Trace Recording

Traces adhere to [`SCHEMA.md`](./SCHEMA.md) and can be captured using the Go recorder in `recorder/`:

```bash
# Build the recorder
cd ~/projects/tmp/ax/viz/recorder
go build -o ax-trace main.go

# Capture a trace while running a swarm recipe
AX_TRACE_RECIPE=1 ./ax-trace -out ../traces/my-run.jsonl &
RECORDER_PID=$!
~/projects/tmp/ax/swarm/05-debate.sh
kill $RECORDER_PID
```
