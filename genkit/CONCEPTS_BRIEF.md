# Multi-Agent Genkit Go Examples on AX & Agent Substrate: Sandboxed EGM Review Panel & In-Cluster A2A Delegation

> **OKF v0.2 Track Metadata & Lineage**: [`okf/genkit.md`](../okf/genkit.md) · **Track Overview**: [`genkit/README.md`](./README.md)

* **Author:** G. H. Chinoy (`ghchinoy`)
* **Date:** 2026-11-07

## Overview

This document defines the architecture for two multi-agent Genkit Go (`cmd/runners/genkit-runner`) examples running on AX and Agent Substrate (`v1.0.0-rc.1`):

1. **Example A (`01-egm-review-panel.sh` — Sandboxed Elephant-Goldfish Design & Review Loop)**: One stateful Elephant task (`elephant-architect`, `allowWriteAccess: true`, durable `/workspace/.genkit/snapshots`) drafts and revises a design specification in `/workspace/DESIGN_SPEC.md`, while three stateless Goldfish tasks (`goldfish-design`, `goldfish-catalyst`, `goldfish-comprehension`, `allowWriteAccess: false`) mount reviewer rubrics from `~/projects/elephant-goldfish-model/agents/*.md` at `.agents/skills/<persona>/SKILL.md`, evaluate the draft over A2A gRPC (`lf.a2a.v1.A2AService/SendStreamingMessage`) using Dotprompt `output.schema`, and suspend back to zero compute after the review wave.
2. **Example B (`02-in-cluster-delegation.sh` — Autonomous In-Sandbox Agent-to-Agent Delegation)**: A coordinator task (`lead-engineer`) connects to an in-sandbox stdio MCP server (`/usr/local/bin/a2a-mcp-bridge`) declared in `Workspace.spec.mcp`. During a single turn, `lead-engineer` invokes the `delegate_to_actor` MCP tool, which dials `atenet-router.ate-system.svc.cluster.local:443` over mTLS using A2A gRPC from inside the gVisor sandbox, wakes a suspended specialist task (`security-specialist`) on demand, and incorporates the specialist's findings without a host-side message relay.

## Analysis

Seven fresh-context Goldfish subagents (`egm-design`, `egm-codebase-details`, `egm-zoom-out`, `egm-comprehension`, `egm-implementation-readiness`, `egm-structural`, and `egm-inventive-catalyst`) audited the initial hypothesis against the `google/ax` and `ax-experiments` codebases. Four primary technical contradictions and failure modes were identified and resolved:

1. **In-Sandbox `atenet-router:443` mTLS, Egress Filtering, and the 32 KiB `AX_WORKSPACE_YAML` Limit (Example B)**:
   * *Contradiction*: Autonomous in-sandbox delegation requires dialing `atenet-router.ate-system.svc.cluster.local:443` over HTTP/2 + mTLS + Protobuf (`lf.a2a.v1.A2AService`), but gVisor sandboxes enforce a default-deny `EgressPolicy`, lack `kubectl` to mint `PodCertificateRequest` credentials, lack Python `grpcio` libraries in `Dockerfile.genkit`, and cap `AX_WORKSPACE_YAML` at 32 KiB (preventing compiled binaries in `Workspace.spec.files`).
   * *Resolution (Preliminary Action + Extraction)*: Compile a static Go stdio MCP binary (`a2a-mcp-bridge`) into the local `localhost:5001/genkit-runner` image at `/usr/local/bin/a2a-mcp-bridge`. Before running Example B, refresh the host `~/.ax/tunnels/*-router-tls.json` credential cache (`spiffe://cluster.local/ns/ax-system/sa/ax-server`), mount that 1.9 KiB JSON file into `lead-engineer`'s workspace at `/workspace/.ax-router-tls.json`, and configure `lead-engineer`'s Substrate `EgressPolicy` with `TlsPassthrough` rules for both `*.googleapis.com:443` and `atenet-router.ate-system.svc.cluster.local:443` / `atenet-router.ate-system.svc:443`. Envoy's `egress_passthrough` chain in `atenet-egress` resolves the SNI via CoreDNS and forwards the raw mTLS stream directly to `atenet-router:443`.
2. **Worker Pool Contention vs. Parallel 3-Goldfish Review Waves (Example A)**:
   * *Contradiction*: Running 1 stateful Elephant + 3 concurrent Goldfish reviewers requires 4 active gVisor workers if the Elephant remains `Running` during the review wave, which starves a 3-replica worker pool.
   * *Resolution (Inversion + Cheap Dispensables)*: After the Elephant produces its initial draft in Turn 1, the orchestrator extracts `/workspace/DESIGN_SPEC.md` and immediately suspends the Elephant (`ax suspend task elephant-architect`), freeing its gVisor worker slot. All 3 Goldfish tasks then execute in parallel across 3 gVisor workers (`ax-workers` scaled to 3 replicas), stream back their structured JSON critiques over A2A gRPC `SendStreamingMessage`, and suspend (`ax suspend`) before `atenet-router` wakes the Elephant on demand for Turn 2.
3. **Stateless Goldfish Isolation vs. Automatic `/workspace/.genkit/snapshots` Persistence (Example A)**:
   * *Risk*: `genkit-runner` unconditionally configures `localstore.NewFileSessionStore` at `/workspace/.genkit/snapshots`, even when `genkit-middleware/filesystem` sets `allowWriteAccess: false`. Reusing an A2A `contextId` across review waves would cause a resumed Goldfish task to reload prior wave conversation history.
   * *Resolution*: The orchestrator assigns a fresh wave-scoped `contextId` (`wave-1-goldfish-design`, etc.) to every Goldfish A2A gRPC request so each review wave runs with zero prior session history, while the Elephant uses a persistent `contextId` (`elephant-session-1`) across `ax suspend` and `ax resume`.
4. **Skill Directory Layout (`<skills.path>/<name>/SKILL.md`) & `AX_WORKSPACE_YAML` Size Budget (Example A)**:
   * *Risk*: `genkit-middleware/skills` requires `<skills.path>/<skill-name>/SKILL.md` subdirectories rather than flat `agents/*.md` files, and inlining all 10 EGM personas (~34 KiB) in one `Workspace` exceeds Substrate's 32 KiB `AX_WORKSPACE_YAML` limit.
   * *Resolution*: Each Goldfish task binds its own dedicated `Workspace` containing only its single assigned persona file mapped to `.agents/skills/<persona>/SKILL.md` (~3–4 KiB per Workspace).

## Goals vs. Non-Goals

* **In-Scope Goals:**
  * Provide a shared Go package (`genkit/internal/axclient`) for Substrate `EgressPolicy` provisioning, `atenet-router` mTLS configuration, and A2A gRPC (`SendMessage` and `SendStreamingMessage`) client calls.
  * Implement and verify Example A (`genkit/01-egm-review-panel.sh` + `genkit/cmd/egm-orchestrator`) exercising 1 Elephant + 3 parallel Goldfish reviewers over A2A gRPC `SendStreamingMessage` with Dotprompt `output.schema` and wave-scoped `contextId` isolation.
  * Implement and verify Example B (`genkit/02-in-cluster-delegation.sh` + `genkit/cmd/a2a-mcp-bridge`) exercising autonomous in-sandbox MCP-to-A2A gRPC delegation across `atenet-router.ate-system.svc.cluster.local:443` with structured telemetry in `/workspace/.genkit/mcp-delegation.jsonl`.
* **Out-of-Scope Non-Goals:**
  * Modifying `ax.proto` or `ax-server` control-plane RPCs (all examples run against the existing `ax.io/v1alpha1` API and `go.ate.dev/substrate v1.0.0-rc.1`).
  * Multi-hour certificate auto-rotation daemons inside task sandboxes (pre-run `podidentity` certificate refresh with 30–60m validity and explicit `NotAfter` logging is sufficient for task runs).

## Alternatives Weighed

* **Inlining all 10 `elephant-goldfish-model/agents/*.md` files into a single shared `Workspace`**: Rejected by author: exceeds Substrate's 32 KiB `AX_WORKSPACE_YAML` environment variable limit and fails `ActorTemplate` creation with `ReasonTemplateCreationFailed`.
* **Implementing the in-sandbox A2A gRPC MCP bridge in Python (`tools/*.py`)**: Rejected by author: `Dockerfile.genkit` (`python:3.12-slim`) includes only Python stdlib without `grpcio` or `protobuf`, and installing pip packages at runtime requires opening wildcard PyPI egress rules. A static Go binary (`a2a-mcp-bridge`) compiled into the local runner image has zero runtime dependencies.
* **Keeping the Elephant task `Running` while all 3 Goldfish tasks execute in parallel**: Rejected by author: requires 4 concurrent gVisor workers for a 3-reviewer wave and wastes an idle worker slot while waiting on Goldfish reviews. Suspending the Elephant before the review wave lets 3 workers run all 3 Goldfish reviewers concurrently and exercises `atenet-router` wake-on-request when delivering the aggregated review findings back to the Elephant.

## Key Decisions & Staging for Next Steps

1. **Shared Go Module (`genkit/go.mod`)**: Consolidate Substrate `EgressPolicy`, router mTLS, and A2A gRPC client code in `genkit/internal/axclient` so both `egm-orchestrator` and `a2a-mcp-bridge` share a single implementation.
2. **Structured JSON Output & Fallback Parsing**: Configure Goldfish tasks with Dotprompt Picoschema under `Task.spec.config.output.schema` (`verdict`, `summary`, `findings`) and strip optional markdown code fences in `egm-orchestrator` before `json.Unmarshal`.
3. **Diagnostic Telemetry**: Log per-wave timing (`wake_ms`, `stream_ms`) in `egm-orchestrator` before suspending Goldfish tasks, and record every in-sandbox delegation call in `/workspace/.genkit/mcp-delegation.jsonl` in `a2a-mcp-bridge`.
