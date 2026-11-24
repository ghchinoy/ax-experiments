---
type: Architecture Guide
title: "Concepts: AX & Agent Substrate 1.0 Developer Mental Model"
description: "Visual architecture explainers (Lustrous Graphviz) mapping Agent Substrate 1.0's 1B-actor multiplexer onto AX's settled v0.4 programming model (#683, #688, #692, #696) and laptop-scale ate-local microVM swarms."
status: stable
tags: [concepts, architecture, substrate, ax, mental-model, graphviz, atelocal]
generated:
  by: human:ghchinoy
  at: 2026-11-21T00:00:00Z
verified:
  - by: human:ghchinoy
    at: 2026-11-21T00:00:00Z
sources:
  - id: substrate-arch
    resource: https://github.com/agent-substrate/substrate/blob/main/docs/concepts/architecture.md
    title: "Agent Substrate 1.0 Architecture (1B actors, <100ms wakeup, WorkerPools, ActorTemplates)"
  - id: substrate-v1
    resource: https://github.com/agent-substrate/substrate/releases/tag/v1.0.0
    title: "Agent Substrate v1.0.0 Release Notes (2026-11-05)"
  - id: substrate-3876
    resource: https://github.com/agent-substrate/substrate/issues/3876
    title: "agent-substrate/substrate#3876: Per-actor environment variables / SystemInfo configuration"
  - id: ax-pr-688
    resource: https://github.com/google/ax/pull/688
    title: "google/ax#688: Push tasks to runners and remove the runner pull protocol"
  - id: ax-issue-683
    resource: https://github.com/google/ax/issues/683
    title: "google/ax#683: Never assume tasks resume with memory (cold-start invariant)"
  - id: ax-issue-696
    resource: https://github.com/google/ax/issues/696
    title: "google/ax#696: Don't split Workspace into its own actor; use ForkTask for branching"
  - id: ax-issue-692
    resource: https://github.com/google/ax/issues/692
    title: "google/ax#692: Long-running, goal-based tasks with steering (TaskService)"
  - id: ax-issue-602
    resource: https://github.com/google/ax/issues/602
    title: "google/ax#602: ate-local zero-Kubernetes local Substrate daemon"
  - id: ax-issue-709
    resource: https://github.com/google/ax/issues/709
    title: "google/ax#709: api: add repeated models to TaskSpec"
  - id: ax-issue-724
    resource: https://github.com/google/ax/issues/724
    title: "google/ax#724: docs: explain how AX differs from Agent Substrate and how it grows into an agentic platform"
  - id: ax-pr-732
    resource: https://github.com/google/ax/pull/732
    title: "google/ax#732: docs: explain how AX relates to Agent Substrate (orthogonal outside task execution; portable across Google, customer clusters, and on-prem)"
  - id: ax-pr-731
    resource: https://github.com/google/ax/pull/731
    title: "google/ax#731: api: align TaskState (< 200) 1-to-1 with Substrate ActorState (Running/Suspended/Crashed)"
  - id: ax-pr-738
    resource: https://github.com/google/ax/pull/738
    title: "google/ax#738: hack/hero-demo: detect task completion inside the sandbox over ax ssh (caller-owned completion)"
  - id: ax-roadmap
    resource: https://github.com/google/ax/blob/main/docs/roadmap.md
    title: "google/ax docs/roadmap.md: Core Specs, Actor Architecture, Agentic Environment, Sessions & Memory, Trajectory Collection"
experiment:
  track: concepts
  location: in-tree
  folder: concepts/
  entrypoints:
    - concepts/README.md
    - concepts/01-substrate-and-ax-mental-model.md
    - concepts/02-the-three-pivots.md
    - concepts/03-datacenter-to-laptop.md
    - concepts/04-from-orchestrator-to-platform.md
---

# Concepts: AX & Agent Substrate 1.0 Developer Mental Model (`concepts/`)

Visual architecture explainers and historical synthesis connecting [Track 1 (`ate-local`)](/ate-local.md), [Track 2a (`swarm`)](/swarm.md), [Track 2b (`genkit`)](/genkit.md), [Track 2c (`dgem`)](/dgem.md), [Track 2d (`agy`)](/agy.md), [Track 3 (`viz`)](/viz.md), [Track 4 (`ax-central`)](/ax-central.md), [Track 5 (`ax-images`)](/ax-images.md), and [Track 6 (`hero-demo`)](/hero-demo.md) to Agent Substrate `1.0` (`2026-11-05`)[^substrate-v1][^substrate-arch], AX's settled `v0.4` design (`#683`, `#688`, `#692`, `#696`),[^ax-issue-683][^ax-pr-688][^ax-issue-692][^ax-issue-696] and its evolution into a portable 7-pillar agentic platform (`#724`, `#732`, `#709`, `docs/roadmap.md`).[^ax-issue-724][^ax-pr-732][^ax-issue-709][^ax-roadmap]

## Artifacts (`concepts/`)

- `concepts/README.md` — 4 Golden Rules for AX developers and canonical upstream reference map.
- `concepts/01-substrate-and-ax-mental-model.md` — Two-plane separation between Substrate `1.0` (`WorkerPool`, `ActorTemplate`, `Actor`, `atenet-router`, `atenet-egress`) and AX (`Task`, `Profile`, `Workspace`, `Model`, `Gateway`).
- `concepts/02-the-three-pivots.md` — How Substrate `1.0`'s immutable `ActorTemplate` contract drove AX from Per-Task Templates $\rightarrow$ `:8081` Pull $\rightarrow$ `#688`/`#700` router-only Inbound Push + `#683` Cold Resume + `#731` compute-aligned `TaskState` + caller-owned completion (`#690`/`#738`),[^ax-pr-731][^ax-pr-738] and the `v1.1` `/run/ate` `SystemInfo` horizon (`substrate#3876`).[^substrate-3876]
- `concepts/03-datacenter-to-laptop.md` — Six empirical lessons from running 10–50 microVM swarm tasks on `ate-local` (`#602`)[^ax-issue-602] and alignment scorecard against upstream AX & Substrate.
- `concepts/04-from-orchestrator-to-platform.md` — Explicit Substrate-vs-AX responsibility boundary and the 7 platform pillars from `google/ax#724` (Sessions, Memory, Multi-task coordination, Input steering, Registries, Models, Trajectory collection) mapped to `docs/roadmap.md` and `ax-experiments` prototypes.
- `concepts/diagrams/*.dot` & `*-{light,dark}.webp` — Five dual-theme Lustrous Graphviz schematics.

[^substrate-arch]: Agent Substrate 1.0 Architecture (1B actors, <100ms wakeup, WorkerPools, ActorTemplates)
[^substrate-v1]: Agent Substrate v1.0.0 Release Notes (2026-11-05)
[^substrate-3876]: agent-substrate/substrate#3876: Per-actor environment variables / SystemInfo configuration
[^ax-pr-688]: google/ax#688: Push tasks to runners and remove the runner pull protocol
[^ax-issue-683]: google/ax#683: Never assume tasks resume with memory (cold-start invariant)
[^ax-issue-696]: google/ax#696: Don't split Workspace into its own actor; use ForkTask for branching
[^ax-issue-692]: google/ax#692: Long-running, goal-based tasks with steering (TaskService)
[^ax-issue-602]: google/ax#602: ate-local zero-Kubernetes local Substrate daemon
[^ax-issue-709]: google/ax#709: api: add repeated models to TaskSpec
[^ax-issue-724]: google/ax#724: docs: explain how AX differs from Agent Substrate and how it grows into an agentic platform
[^ax-pr-732]: google/ax#732: docs: explain how AX relates to Agent Substrate (orthogonal outside task execution; portable across Google, customer clusters, and on-prem)
[^ax-pr-731]: google/ax#731: api: align TaskState (< 200) 1-to-1 with Substrate ActorState (Running/Suspended/Crashed)
[^ax-pr-738]: google/ax#738: hack/hero-demo: detect task completion inside the sandbox over ax ssh (caller-owned completion)
[^ax-roadmap]: google/ax docs/roadmap.md
