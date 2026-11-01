---
okf_version: "0.2"
---

# AX Experiments — OKF v0.2 Knowledge Bundle

## In-Tree Experiment Tracks (`ax-experiments/`)

* [Track 1: Local Apple Container Substrate (ate-local)](/ate-local.md) - Native macOS Local Substrate (`ateapipb.ControlServer`) backed by Apple `container` microVMs and PostgreSQL (`google/ax#526`).
* [Track 2a: Multi-Agent Swarm Recipes (01–08)](/swarm.md) - Eight runnable multi-agent swarm and sandbox boundary recipes (`swarm/01..08`) on Apple `container` microVMs.
* [Track 2b: Declarative Genkit Go Runner (genkit-runner)](/genkit.md) - Declarative Dotprompt agents on AX with A2A JSON-RPC, Genkit HTTP, MCP, skills, and suspend/resume session snapshots (`google/ax#538`).
* [Track 3: Swarm Telemetry, Correlation IDs & Visual Replay](/viz.md) - JSONL trace event schema, Go recorder (`ax-trace`), Lit 3 + Force-Graph + Cytoscape CoSE replay UI, and swarm lineage RFC.

## External Companion Projects (`~/projects/*`)

* [Track 4: AX Central — Desktop Control Plane, Task Designer & Podman Shim](/ax-central.md) - Standalone Wails v2 + Lit 3 + xterm.js + WebMCP desktop app (`~/projects/ax-central`) for designing, deploying, and visualizing AX Tasks/Workspaces/Models and shimming `docker`-to-`podman`.
