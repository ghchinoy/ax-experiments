---
type: External Experiment
title: "Track 7: Substrate Local — Standalone Zero-Kubernetes Agent Substrate v1.0.0 Daemon (~/projects/substrate-local)"
description: "Standalone Go implementation of go.ate.dev/substrate v1.0.0 ControlServer and embedded atenet-router (h2c) over macOS Apple container and rootless Podman, allowing unmodified upstream google/ax binaries to run locally in ~2 seconds with zero Kubernetes or fork rebases."
status: stable
tags: [substrate-local, atelocal, apple-container, podman, substrate, macos, microvm, external]
generated:
  by: human:ghchinoy
  at: 2026-11-25T00:00:00Z
verified:
  - by: human:ghchinoy
    at: 2026-11-25T00:00:00Z
sources:
  - id: ghchinoy-substrate-local
    resource: https://github.com/ghchinoy/substrate-local
    title: "ghchinoy/substrate-local: Standalone Agent Substrate v1.0.0 Control + Router daemon"
  - id: upstream-substrate
    resource: https://github.com/agent-substrate/substrate
    title: "agent-substrate/substrate: Agent Substrate v1.0.0 Control API"
  - id: ax-issue-602
    resource: https://github.com/google/ax/issues/602
    title: "google/ax#602: ate-local zero-Kubernetes local Substrate daemon"
  - id: ax-issue-712
    resource: https://github.com/google/ax/issues/712
    title: "google/ax#712: ax local start should not require Docker"
experiment:
  track: substrate-local
  location: external
  local_path: ~/projects/substrate-local
  entrypoints:
    - Makefile
    - cmd/substrate-local/main.go
    - scripts/ax-stack.sh
    - scripts/test-ax-compat.sh
    - examples/substrate-local.yaml
  upstream:
    repo: agent-substrate/substrate
    issues: [483, 3876]
---

# Track 7: Substrate Local (`~/projects/substrate-local`)

## Hypothesis & Goal

Spin the zero-Kubernetes `ate-local` daemon out of the `ghchinoy/ax` fork into a standalone Go module ([`ghchinoy/substrate-local`](https://github.com/ghchinoy/substrate-local)) that depends **only** on the frozen `go.ate.dev/substrate v1.0.0` API (`ateapi/v1.ControlServer`) and embedded `atenet-router` (`h2c`), with **zero dependency on `google/ax` internal packages**.[^ghchinoy-substrate-local][^upstream-substrate]

This lets **unmodified upstream `google/ax` binaries** (`ax-server --substrate-endpoint 127.0.0.1:50051 --substrate-plaintext --router-url http://127.0.0.1:50051`) run on macOS Apple `container` microVMs and rootless Podman in ~2 seconds—eliminating fork-rebase churn against `google/ax` while directly answering [`google/ax#602`](https://github.com/google/ax/issues/602) and [`google/ax#712`](https://github.com/google/ax/issues/712).[^ax-issue-602][^ax-issue-712]

## External Project Structure (`~/projects/substrate-local`)

- `cmd/substrate-local/` & `pkg/sublocal/` — Standalone `ateapi/v1.ControlServer` + `h2c` `atenet-router` daemon supporting Apple `container` and rootless `podman`, pre-boot `/workspace` snapshot hydration, and `Tag` snapshots.
- `scripts/ax-stack.sh` — Single- and dual-cluster (`up` / `multi-up` / `status` / `down` / `reset`) launcher pairing `substrate-local` with unmodified upstream `ax-server` and `postgres:17-alpine`.
- `scripts/test-ax-compat.sh` (`make test-compat`) — Upstream `google/ax` compatibility regression suite + GitHub Actions CI.
- `examples/substrate-local.yaml` & `examples/task-local.yaml` — Ready-to-run daemon config and smoke task manifest.

## Verification Commands (in `~/projects/substrate-local`)

```bash
cd ~/projects/substrate-local
make vet && make test       # Go vet + pkg/sublocal unit/live tests
make test-compat            # Upstream google/ax compatibility regression suite
make up && make status      # Start Postgres + substrate-local + upstream ax-server
```

## Related Experiment Tracks

- Graduated from [Track 1: Local Apple Container Substrate (ate-local)](/ate-local.md), decoupling local microVM execution from `ghchinoy/ax` fork maintenance.
- Serves as the zero-Kubernetes local compute backend for [Track 4: AX Central — Desktop Control Plane, Task Designer & Podman Shim](/ax-central.md), [Track 2a: Multi-Agent Swarm Recipes (01–08)](/swarm.md), [Track 2b: Declarative Genkit Go Runner (genkit-runner)](/genkit.md), and [Track 6: End-to-End 5/5 Live AX v0.1 Hero Demo Harness (hero-demo)](/hero-demo.md).

[^ghchinoy-substrate-local]: ghchinoy/substrate-local: Standalone Agent Substrate v1.0.0 Control + Router daemon
[^upstream-substrate]: agent-substrate/substrate: Agent Substrate v1.0.0 Control API
[^ax-issue-602]: google/ax#602: ate-local zero-Kubernetes local Substrate daemon
[^ax-issue-712]: google/ax#712: ax local start should not require Docker
