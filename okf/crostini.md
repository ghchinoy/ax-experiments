---
type: Experiment Track
title: "Track 1b: Local Chromebook / Crostini Kind + Agent Substrate Stack (crostini)"
description: "Empirically verified guide and bootstrap automation for running AX + Agent Substrate (v1.0.0-rc.1) locally on a Chromebook Linux (Crostini / Bagels KVM) VM with Debian 13 (trixie), Docker overlay2 on btrfs, Kind, and gVisor sandboxes."
status: stable
tags: [crostini, chromebook, debian-trixie, kind, substrate, gvisor, btrfs]
generated:
  by: human:ghchinoy
  at: 2026-11-06T00:00:00Z
verified:
  - by: human:ghchinoy
    at: 2026-11-06T00:00:00Z
sources:
  - id: upstream-ax
    resource: https://github.com/google/ax
    title: "google/ax: AX declarative orchestrator for sandboxed agent tasks"
  - id: upstream-substrate
    resource: https://github.com/agent-substrate/substrate
    title: "agent-substrate/substrate: Agent Substrate v1.0.0-rc.1"
  - id: ax-pr-553
    resource: https://github.com/google/ax/pull/553
    title: "google/ax#553: Bump substrate to v1.0.0-rc.1 and adapt to Substrate 1.0 changes"
experiment:
  track: crostini
  location: in-tree
  folder: crostini/
  beads:
    - ax-experiments-c0h.6
  entrypoints:
    - crostini/README.md
    - crostini/GUIDE.md
    - crostini/setup-crostini.sh
    - crostini/samples/01-sandbox-relay.sh
    - crostini/samples/02-genkit-a2a-grpc.sh
    - crostini/samples/a2a-duo/main.go
  upstream:
    repo: google/ax
    base_commit: 241bc4d
    issues: [538]
    prs: [553]
  forks:
    - repo: ghchinoy/ax
      branch: main
    - repo: ghchinoy/ax
      branch: feat/genkit-runner
---

# Track 1b: Local Chromebook / Crostini Kind + Agent Substrate Stack (`crostini`)

## Hypothesis & Goal

Validate whether a standard **Chromebook Linux development environment (Crostini / Bagels KVM VM)** running Debian 13 (`trixie`) on `x86_64` (`12 vCPUs`, `14 GiB` RAM, `btrfs` rootfs) can run the full upstream **[AX](https://github.com/google/ax)** control plane and **[Agent Substrate](https://github.com/agent-substrate/substrate)** (`v1.0.0-rc.1`) locally with real **gVisor** (`runsc`) sandboxes, `atenet-router` mTLS ingress, in-cluster RustFS volume snapshots, and multi-agent **Genkit Go** tasks communicating over the **A2A gRPC transport** (`lf.a2a.v1.A2AService`).[^upstream-ax][^upstream-substrate][^ax-pr-553]

## Repository Artifacts (`crostini/`)

- `crostini/README.md` — Track overview and quickstart commands.
- `crostini/GUIDE.md` — End-to-end guide covering pre-flight kernel/virtualization audit, Debian 13 `docker-cli`/`docker-buildx` packaging split, socket ACLs, Crostini resource tuning (`AX_WORKER_REPLICAS=2`, `SUBSTRATE_IMAGE_CACHE_DIR`), Substrate `v1.0.0-rc.1` `EgressPolicy` configuration, and empirical timings.
- `crostini/setup-crostini.sh` — Idempotent setup script that installs prerequisites, provisions Kind + Substrate + AX, and prunes intermediate Docker BuildKit cache.
- `crostini/samples/01-sandbox-relay.sh` — Zero-key two-task gVisor handoff pipeline (`repo-scanner` → `release-builder`) with SHA-256 verification and RustFS snapshot persistence.
- `crostini/samples/02-genkit-a2a-grpc.sh` & `crostini/samples/a2a-duo/main.go` — Two declarative `genkit-runner` tasks (`coder-agent` ↔ `auditor-agent`) conversing over **A2A gRPC (`lf.a2a.v1.A2AService`)** through `atenet-router` mTLS, including `ax suspend` scale-to-zero and A2A gRPC wake-on-request.

## Empirical Outcomes (`penguin`, Intel Core i5-1245U, 14 GiB RAM)

- **Virtualization Topology**: Direct KVM guest (`systemd-detect-virt -v` = `kvm`, container = `none`), full UID map (`0 0 4294967295`), `cgroup2fs`, and Docker `26.1.5+dfsg1` using `overlay2` over `btrfs`.
- **Cold Cluster Provisioning (`setup-e2e-kind.sh`)**: `12m 00.5s` (compiles Rust `substrate-envoy-egress-policy` + 10 Go images and caches `538 MB` in `~/.cache/substrate-registry`).
- **Warm Cluster Redeploy (`setup-e2e-kind.sh`)**: `58.8s`.
- **Interactive Lifecycle Demo (`./demo.sh`)**: `7.81s` (`apply` → `resume` on gVisor `4.19.0-gvisor` → 3× `ax ssh` over `atenet-router` → RustFS snapshot `suspend`).
- **Sample 1 (`01-sandbox-relay.sh`)**: `9.68s` across two gVisor sandboxes (`repo-scanner` + `release-builder`).
- **Sample 2 (`02-genkit-a2a-grpc.sh`)**: `35.23s` for 3-turn `coder-agent` ↔ `auditor-agent` code fix + security review over **A2A gRPC** (`lf.a2a.v1.A2AService`) with mid-session `ax suspend` and wake-on-request.
- **Full Upstream E2E Test Suite (`make e2e-run`)**: `32.63s` (all 8 test suites passing).

## Related Experiment Tracks

- Complements [Track 1: Local Apple Container Substrate (ate-local)](/ate-local.md) by providing a full Kubernetes + gVisor local environment on ChromeOS / Linux.
- Supports local testing for [Track 2b: Declarative Genkit Go Runner (genkit-runner)](/genkit.md).

[^upstream-ax]: google/ax: AX declarative orchestrator for sandboxed agent tasks
[^upstream-substrate]: agent-substrate/substrate: Agent Substrate v1.0.0-rc.1
[^ax-pr-553]: google/ax#553: Bump substrate to v1.0.0-rc.1 and adapt to Substrate 1.0 changes
