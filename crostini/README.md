# Running AX & Agent Substrate Locally on Chromebook (Crostini / Bagels VM)

> **OKF v0.2 Track Metadata & Lineage**: [`okf/crostini.md`](../okf/crostini.md) · **Bundle Index**: [`okf/index.md`](../okf/index.md)

This track documents, scripts, and empirically validates running the full **[AX](https://github.com/google/ax)** control plane and **[Agent Substrate](https://github.com/agent-substrate/substrate)** (`v1.0.0-rc.1`) locally on a **Chromebook Linux development environment (Crostini / Bagels KVM VM)** running Debian 13 (`trixie`).

Unlike legacy LXD/Termina Crostini setups that nested an unprivileged LXC container inside a VM, modern ChromeOS "Bagels" Linux runs `penguin` directly as a privileged KVM guest (`systemd-detect-virt -v` = `kvm`, `systemd-detect-virt -c` = `none`, full root UID map `0 0 4294967295`) with `cgroup2fs`, `/dev/kvm`, `/dev/net/tun`, and `/dev/fuse` exposed out of the box.

---

## Documents & Scripts in This Folder

| File | Purpose |
|---|---|
| [`GUIDE.md`](./GUIDE.md) | Step-by-step guide, pre-flight audit, Crostini/btrfs quirks, resource tuning, multi-agent samples, and empirical measurements. |
| [`setup-crostini.sh`](./setup-crostini.sh) | Idempotent setup script that installs prerequisites (`docker.io`, `docker-cli`, `docker-buildx`, `gettext-base`, `kubectl`, `kind`) and provisions Kind + Substrate + AX tuned for a Chromebook VM. |
| [`samples/01-sandbox-relay.sh`](./samples/01-sandbox-relay.sh) | **Sample 1 (Zero-Key)**: Two gVisor tasks (`repo-scanner` → `release-builder`) exchanging a SHA-256 verified JSON artifact across sandboxes with RustFS checkpointing (`9.7s`). |
| [`samples/02-genkit-a2a-grpc.sh`](./samples/02-genkit-a2a-grpc.sh) | **Sample 2 (`genkit-runner` + A2A gRPC)**: Two declarative Dotprompt agents (`coder-agent` ↔ `auditor-agent`) conversing over **A2A gRPC (`lf.a2a.v1.A2AService`)** through `atenet-router` mTLS, with scale-to-zero (`ax suspend`) and wake-on-request (`35.2s`). |
| [`samples/a2a-duo/main.go`](./samples/a2a-duo/main.go) | Go orchestrator using `a2agrpc/v1` (`WithGRPCTransport`) + `ate-target-actor` gRPC metadata and Substrate `CreateActorEgressPolicy` (`*.googleapis.com:443`). |

---

## Quick Start

```bash
# 1. Install prerequisites and provision Kind + Substrate + AX (tuned for Crostini)
./crostini/setup-crostini.sh

# 2. Load the local cluster environment into your shell
source ~/projects/ax/.tmp/e2e.env
export PATH="$(dirname "$AX_BIN"):$PATH"

# 3. Run Sample 1: Zero-Key Two-Sandbox Handoff Pipeline (~9.7s)
./crostini/samples/01-sandbox-relay.sh

# 4. Run Sample 2: Two Genkit Agents Conversing Over A2A gRPC (~35.2s)
./crostini/samples/02-genkit-a2a-grpc.sh
```
