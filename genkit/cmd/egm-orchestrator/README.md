# `egm-orchestrator` Multi-Agent A2A gRPC Driver Package

## Overview
Host-side Go driver (`egm-orchestrator`) for [`../../01-egm-review-panel.sh`](../../01-egm-review-panel.sh) and [`../../02-in-cluster-delegation.sh`](../../02-in-cluster-delegation.sh) that coordinates multi-agent Genkit Go tasks on AX and Agent Substrate over A2A gRPC (`lf.a2a.v1.A2AService/SendStreamingMessage`).

## Interface
- **Binary Entrypoint**: `main.go` (`egm-orchestrator`)
- **Flags**:
  - `-mode <egm-panel|in-cluster-delegation>` *(default `egm-panel`)*: Selects Example 01 (1 Elephant + 3 parallel Goldfish reviewers with residency inversion) or Example 02 (autonomous in-sandbox MCP-to-A2A gRPC delegation).
  - `-atespace <name>` *(default `default`)*: Target AX atespace.
  - `-ax-namespace <name>` *(default `ax-system`)*: Kubernetes namespace running `ax-server`.
  - `-kube-context <name>` *(default `kind-ax-e2e`)*: Kubernetes context for `kubectl` port-forwarding and token minting.
  - `-ax-bin <path>` *(default `ax`)*: Path to the `ax` CLI binary.

## Invariants
- Assigns a fresh wave-scoped `contextId` (`wave-<n>-<reviewer>`) to every Goldfish A2A gRPC request so stateless Goldfish tasks never reload prior review-wave history from `/workspace/.genkit/snapshots`.
- Suspends `elephant-architect` before launching the 3 parallel Goldfish reviewers so all 4 tasks execute within a 3-worker Substrate pool.

## Side Effects
- Configures Substrate `EgressPolicy` rules via [`../../internal/axclient/README.md`](../../internal/axclient/README.md), opens temporary `kubectl port-forward` tunnels to `atenet-router`, and invokes `ax suspend` / `ax ssh` on target tasks.

## Verification
- Run: `go -C genkit vet ./cmd/egm-orchestrator && go -C genkit build -o /dev/null ./cmd/egm-orchestrator`
