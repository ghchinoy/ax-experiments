---
type: Architecture Guide
title: "Concepts: AX & Agent Substrate 1.0 Developer Mental Model"
description: "Visual architecture explainers (Luminous Graphviz) mapping Agent Substrate 1.0's 1B-actor multiplexer onto AX's settled v0.4 programming model (#683, #688, #692, #696) and laptop-scale ate-local microVM swarms."
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
experiment:
  track: concepts
  location: in-tree
  folder: concepts/
  entrypoints:
    - concepts/README.md
    - concepts/01-substrate-and-ax-mental-model.md
    - concepts/02-the-three-pivots.md
    - concepts/03-datacenter-to-laptop.md
---

# Concepts: AX & Agent Substrate 1.0 Developer Mental Model (`concepts/`)

Visual architecture explainers and historical synthesis connecting [Track 1 (`ate-local`)](/ate-local.md), [Track 2a (`swarm`)](/swarm.md), [Track 2b (`genkit`)](/genkit.md), [Track 4 (`ax-central`)](/ax-central.md), and [Track 6 (`hero-demo`)](/hero-demo.md) to Agent Substrate `1.0` (`2026-11-05`)[^substrate-v1][^substrate-arch] and AX's settled `v0.4` design (`#683`, `#688`, `#692`, `#696`).[^ax-issue-683][^ax-pr-688][^ax-issue-692][^ax-issue-696]

## Artifacts (`concepts/`)

- `concepts/README.md` — 4 Golden Rules for AX developers and canonical upstream reference map.
- `concepts/01-substrate-and-ax-mental-model.md` — Two-plane separation between Substrate `1.0` (`WorkerPool`, `ActorTemplate`, `Actor`, `atenet-router`, `atenet-egress`) and AX (`Task`, `Profile`, `Workspace`, `Gateway`).
- `concepts/02-the-three-pivots.md` — How Substrate `1.0`'s immutable `ActorTemplate` contract drove AX from Per-Task Templates $\rightarrow$ `:8081` Pull $\rightarrow$ `#688` (`2ede873`) Inbound Push + `#683` Cold Resume + `#696` `ForkTask`, and the `v1.1` `/run/ate` `SystemInfo` horizon (`substrate#3876`).[^substrate-3876]
- `concepts/03-datacenter-to-laptop.md` — Six empirical lessons from running 10–50 microVM swarm tasks on `ate-local` (`#602`)[^ax-issue-602] and alignment scorecard against upstream AX & Substrate.
- `concepts/diagrams/*.dot` & `*-{light,dark}.webp` — Four dual-theme Luminous Graphviz schematics.

[^substrate-arch]: Agent Substrate 1.0 Architecture (1B actors, <100ms wakeup, WorkerPools, ActorTemplates)
[^substrate-v1]: Agent Substrate v1.0.0 Release Notes (2026-11-05)
[^substrate-3876]: agent-substrate/substrate#3876: Per-actor environment variables / SystemInfo configuration
[^ax-pr-688]: google/ax#688: Push tasks to runners and remove the runner pull protocol
[^ax-issue-683]: google/ax#683: Never assume tasks resume with memory (cold-start invariant)
[^ax-issue-696]: google/ax#696: Don't split Workspace into its own actor; use ForkTask for branching
[^ax-issue-692]: google/ax#692: Long-running, goal-based tasks with steering (TaskService)
[^ax-issue-602]: google/ax#602: ate-local zero-Kubernetes local Substrate daemon
