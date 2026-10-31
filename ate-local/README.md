---
type: Experiment Track
title: "ate-local: Native macOS Local Substrate on Apple Container"
description: "Overview and quickstart for running the AX control plane and ateapipb.ControlServer on Apple Silicon using native macOS container microVMs and PostgreSQL."
status: stable
tags: [atelocal, apple-container, substrate, macos, microvm]
generated:
  by: human:ghchinoy
  at: 2026-10-31T00:00:00Z
verified:
  - by: human:ghchinoy
    at: 2026-10-31T00:00:00Z
sources:
  - id: ax-issue-526
    resource: https://github.com/google/ax/issues/526
    title: "google/ax#526: ax local start/status/stop"
  - id: fork-atelocal
    resource: https://github.com/ghchinoy/ax/tree/feat/ate-local-apple-container
    title: "ghchinoy/ax:feat/ate-local-apple-container"
experiment:
  track: ate-local
  beads:
    - ax-experiments-1rx
    - ax-experiments-1rx.1
    - ax-experiments-1rx.2
    - ax-experiments-1rx.3
  upstream:
    repo: google/ax
    base_commit: f0228f1
    issues: [526, 515, 517, 532, 536]
    prs: [504]
  forks:
    - repo: ghchinoy/ax
      branch: feat/ate-local-apple-container
---

# `ate-local`: Native macOS Local Substrate on Apple Container

This experiment track prototypes and benchmarks **`ate-local`**, a lightweight Go daemon implementing the **Agent Substrate Control gRPC API** (`go.ate.dev/substrate/pkg/proto/ateapipb.ControlServer`) backed by macOS's native **Apple `container`** runtime (`/usr/local/bin/container`).

With `ate-local`, an AX developer on an Apple Silicon Mac can boot the full AX stack (`postgres:17-alpine` + `ate-local` + `ax-server`) in ~3.3 seconds and run isolated Linux microVM tasks (`192.168.64.x` `vmnet` bridge) with zero Kubernetes (`kind`), Docker Desktop, gVisor, or cloud infrastructure.

---

## Documents in This Folder

| Document | Purpose |
|---|---|
| [`PROPOSAL.md`](/ate-local/PROPOSAL.md) | Full architectural proposal, Substrate concept mapping, developer glidepath analysis, and Apple Silicon performance benchmarks. |
| [`TESTING.md`](/ate-local/TESTING.md) | Step-by-step verification guide: automated unit tests, live Apple `container` microVM integration tests, and full local stack walkthrough. |
| [`archive/prior-proposal.md`](/ate-local/archive/prior-proposal.md) | Archived initial `ate-local` design draft. |
| [`archive/glidepath.md`](/ate-local/archive/glidepath.md) | Archived developer adoption funnel ("glidepath") notes. |

---

## Quick Verification

From your [`ghchinoy/ax`](https://github.com/ghchinoy/ax) checkout on the `feat/ate-local-apple-container` branch:

```bash
cd ~/projects/ax
git checkout feat/ate-local-apple-container

# 1. Run automated unit + live Apple container microVM tests
go test -v ./internal/atelocal/...

# 2. Boot the local stack (PostgreSQL 17 + ate-local :50051 + ax-server :8090)
make local-up
source .ax-local/env
make local-status
```

Once the local stack is running, continue to [`/swarm/README.md`](/swarm/README.md) to run multi-agent swarm recipes (`01`–`08`) or [`/genkit/README.md`](/genkit/README.md) to run the declarative Genkit Go runner (`#538`) inside an Apple container microVM.
