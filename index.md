---
okf_version: "0.2"
---

# Repository Governance & Index

* [AX Experiments: Multi-Agent Swarms, Declarative Runners, Telemetry & Local Substrate](/README.md) - Companion R&D repository for prototyping, stress-testing, and visualizing AX and Agent Substrate across local Apple container microVMs, multi-agent swarms, declarative Genkit Go runners, and trace replay.
* [AX Experiments — Agent Contract](/AGENTS.md) - Agent workflow contract, per-folder OKF v0.2 metadata ruleset, optional fork/branch/upstream lineage schema, and Beads (`bd`) experiment tracking guidelines.

# Track 1: Local Apple Container Substrate (`ate-local/`)

* [ate-local: Native macOS Local Substrate on Apple Container](/ate-local/README.md) - Overview and quickstart for running the AX control plane and `ateapipb.ControlServer` on Apple Silicon using native macOS `container` microVMs and PostgreSQL.
* [Feature Proposal: Native macOS Local Development for AX via Apple Container & ate-local](/ate-local/PROPOSAL.md) - Architectural proposal, Substrate concept mapping, and empirical Apple Silicon benchmarks for `ate-local`.
* [Testing ate-local: AX on Apple Container](/ate-local/TESTING.md) - Step-by-step verification guide covering automated unit/live microVM tests and the full local stack walkthrough.
* [Prior Proposal Draft: ate-local](/ate-local/archive/prior-proposal.md) - Archived initial design draft for `ate-local` on Apple container.
* [The Developer Glidepath Positioning](/ate-local/archive/glidepath.md) - Archived adoption-funnel analysis from local macOS prototyping to production GKE Agent Substrate.

# Track 2a: Multi-Agent Swarm Recipes (`swarm/`)

* [AX Agent Swarm Kit on Apple Container](/swarm/README.md) - Catalog and quickstart for 8 standalone multi-agent swarm and sandbox boundary recipes (`01`–`08`) on Apple `container`.
* [Developer Guide: An Intro to AX on Apple Container](/swarm/GUIDE.md) - Deep-dive guide to AX primitives, three swarm orchestration patterns, and measured outputs across recipes `01`–`08`.

# Track 2b: Declarative Genkit Go Runner (`genkit/`)

* [Declarative Genkit Go Runner on AX (`genkit-runner`)](/genkit/README.md) - Overview, manifest catalog, and quickstart for running declarative Dotprompt agents with MCP, skills, A2A JSON-RPC, and durable session snapshots on Apple container microVMs or GCE Kind clusters.
* [Tutorial: Declarative, Suspendable AI Agents on AX with Genkit Go](/genkit/TUTORIAL.md) - Three-part end-to-end tutorial covering local Linux execution, GCE Kind + Agent Substrate v0.6.0 wake-on-request, and macOS Apple container microVM verification.

# Track 3: Swarm Telemetry & Visual Replay (`viz/`)

* [AX Swarm Visualizer](/viz/README.md) - Interactive Lit 3 + Force-Graph + Cytoscape CoSE replay web application and Go trace recorder (`ax-trace`) quickstart.
* [AX Swarm Execution Trace Schema (`trace.jsonl`)](/viz/SCHEMA.md) - JSON Lines event schema capturing AX infrastructure lifecycle transitions and inter-agent swarm messages.
* [Architectural Friction Report: Correlation IDs, Swarm Lineage, and Observability in AX](/viz/FRICTION-REPORT.md) - Post-implementation analysis and RFC proposing `correlation_id`, `parent_task`, W3C TraceContext propagation, and AX-mediated inter-actor messaging.
