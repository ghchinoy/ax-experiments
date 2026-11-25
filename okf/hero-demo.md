---
type: Experiment Track
title: "Track 6: End-to-End 5/5 Live AX v0.1 Hero Demo Harness (hero-demo)"
description: "Live 5/5 PASS execution of upstream google/ax's v0.1 Hero Demo (google/ax#590) across Apple container microVMs (ate-local, google/ax#602), warm Substrate v1.0 workspace snapshot Tags, digest-pinned Genkit Go multi-turn sessions across suspend/resume, stock python:3.12-slim runner injection, and Podman/Kubernetes cluster promotion."
status: stable
tags: [hero-demo, v1alpha1, ate-local, snapshots, genkit-runner, podman, multi-cluster]
generated:
  by: human:ghchinoy
  at: 2026-11-15T00:00:00Z
verified:
  - by: human:ghchinoy
    at: 2026-11-15T00:00:00Z
sources:
  - id: ax-pr-590
    resource: https://github.com/google/ax/pull/590
    title: "google/ax#590: hack: add the v0.1 hero demo harness"
  - id: ax-issue-602
    resource: https://github.com/google/ax/issues/602
    title: "google/ax#602: Local macOS Apple container & Podman Substrate (ate-local)"
  - id: ax-images-issue-1
    resource: https://github.com/ghchinoy/ax-images/issues/1
    title: "ghchinoy/ax-images#1: align runners with AX v1alpha1 Epic #563 and publish v0.2.0 digests"
experiment:
  track: hero-demo
  location: in-tree
  folder: hero-demo/
  beads:
    - ax-experiments-ibo
    - ax-experiments-ibo.1
    - ax-experiments-ibo.2
  entrypoints:
    - hero-demo/run-live.sh
    - hero-demo/workspace.yaml
    - hero-demo/task-starter.yaml
    - hero-demo/task-custom.yaml
    - genkit/cmd/ws-tag/main.go
  upstream:
    repo: google/ax
    base_commit: 9a65684
    issues: [526, 538, 563, 602]
    prs: [590]
  forks:
    - repo: ghchinoy/ax
      branch: feat/ate-local-apple-container
---

# Track 6: End-to-End 5/5 Live AX v0.1 Hero Demo Harness (`hero-demo/`)

## Hypothesis & Goal

Replace every `🟡 STUB` in upstream `google/ax/hack/hero-demo/run.sh` (`#590`) with live, verifiable execution (`5/5 🟢 PASS`) across local Apple `container` microVMs, immutable Agent Substrate `v1.0.0` workspace snapshot `Tag`s, multi-turn agent sessions durable across `ax suspend`/`ax resume`, unmodified stock images (`python:3.12-slim`), and multi-cluster promotion (`Apple container` $\rightarrow$ `Podman` / Kubernetes).[^ax-pr-590][^ax-issue-602][^ax-images-issue-1]

## Five Verified Capabilities

1. **Dual-Cluster Local Control Plane (`Step 1`)**: Boots Cluster A (`Apple container`) and Cluster B (`Podman`) via [Track 1: Local Apple Container Substrate (ate-local)](/ate-local.md) with isolated Prometheus `--metrics-addr` bindings and embedded `atenet-router`, paired with [Track 4: AX Central — Desktop Control Plane, Task Designer & Podman Shim](/ax-central.md).
2. **Pre-Boot Warm Workspace `Tag` Hydration (`Step 2`)**: Applies `hero-demo-ws` (`spec.setup.commands`), captures an immutable `Tag` (`hero-demo-ws-warm`, `SNAPSHOT_STORAGE_STATE_COMPLETED`) via `genkit/cmd/ws-tag`, verifies wake-on-request (`HTTP 200`) over `atenet-router`, and pre-mounts the warm snapshot before PID 1 boots.
3. **Digest-Pinned Starter Agent & Durable Session (`Step 3`)**: Runs `ghcr.io/ghchinoy/ax-images/genkit-runner@sha256:2620b7bc...` (`v0.3.0`) from [Track 5: AX Images — Multi-Arch Task Image Repository (ghcr.io/ghchinoy/ax-images)](/ax-images.md) and [Track 2b: Declarative Genkit Go Runner (genkit-runner)](/genkit.md) to implement `subtract(a, b)` on Turn 1, survive `ax suspend task` $\rightarrow$ `ax resume task`, and recall Turn 1 history on Turn 2.
4. **Stock Custom Image Injection (`Step 4`)**: Runs upstream's unmodified `task-custom.yaml` (`image: python:3.12-slim`, which lacks both `ax-task-runner` and `git`), proving automatic `/usr/local/bin/ax-task-runner` injection and warm snapshot attachment (`workspace already initialized; skipping maiden run setup`, `Ran 2 tests ... OK`).
5. **Unchanged Multi-Cluster Promotion (`Step 5`)**: Applies `workspace.yaml` and `task-custom.yaml` unchanged to Cluster B (`Podman` runtime or Kubernetes `--remote-context`) and verifies `2/2` unit tests pass on the promoted cluster.

[^ax-pr-590]: google/ax#590: hack: add the v0.1 hero demo harness
[^ax-issue-602]: google/ax#602: Local macOS Apple container & Podman Substrate (ate-local)
[^ax-images-issue-1]: ghchinoy/ax-images#1: align runners with AX v1alpha1 Epic #563 and publish v0.2.0 digests
