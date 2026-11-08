# Track 2d (`ax-experiments/agy/`): Antigravity (`agy`) Coding Agents on AX with Cascading `dgem` Safety Gates

> **OKF v0.2 Track Metadata & Lineage**: [`okf/agy.md`](../okf/agy.md) · **Track Overview**: [`agy/README.md`](./README.md)

* **Author:** G. H. Chinoy (`ghchinoy`)
* **Date:** 2026-11-08

## Overview

This document defines the architecture for Track 2d (`ax-experiments/agy/`), which runs Google Antigravity coding agents inside AX sandboxes across two execution surfaces and two substrates in two phased stages:

1. **Two Antigravity Surfaces**:
   * **Surface A — Turnkey `ax-images/antigravity` Runner (`ghcr.io/rakyll/ax-images/antigravity@sha256:8025a987...`)**: Uses the Gemini Interactions API (`client.Interactions` in Go with `agent: "antigravity-preview-09-2026"`) and executes `run_shell`, `read_file`, `write_file`, and `edit_file` inside `/workspace`.
   * **Surface B — Antigravity CLI (`agy`) & Python SDK (`google.antigravity`)**: Uses `.agents/hooks.json` (`PreToolUse` command hook) and the Python SDK lifecycle/policy adapters (`@hooks.pre_tool_call_decide` and `policy.ask_user("run_command", handler=...)`) from `~/projects/dgem/examples/agy-safety-gate/`.
2. **Two Execution Substrates**:
   * **Substrate 1 — macOS `ate-local` (Apple `container` microVMs)**: Reaches the host `dgem serve` gateway over the `vmnet` bridge (`http://192.168.64.1:8095`).
   * **Substrate 2 — Kubernetes `Kind + Agent Substrate` (`v1.0.0-rc.1` `runsc` gVisor sandboxes)**: Enforces default-deny `EgressPolicy` (`TlsPassthroughRule` on port `443` and `HttpRule` on port `8095`) and requires `@sha256:` image digest pinning.
3. **Two Phased Stages + `ax-central` Templates**:
   * **Phase 1 (`01-phase1-baseline.sh` — Non-Decision Baseline)**: Runs an un-gated Antigravity coding task on AX (`GEMINI_API_KEY` only, zero `dgem` dependency) that inspects a repository, fixes a failing test, and writes `/workspace/agent-output.md`, while exposing why un-gated `run_shell` / `run_command` execution inside a sandbox is vulnerable to indirect prompt injection (`<untrusted_data>`) and secret exfiltration.
   * **Phase 2 (`02-phase2-dgem-safety-gate.sh` — Cascading `dgem` Safety Gate + `ax ssh` HITL)**: Protects every tool call with a 4-tier policy cascade: **Stage 0** (`<1 ms` deterministic static allow/deny) $\to$ **Stage 1** (`dgem` 2-slot `templates/tool_safety_gate.json.tmpl` evaluating `action_hazard` $\times$ `intent_origin` with `Hesitation %` $= H / \ln K < 16\%$) $\to$ **Stage 2** (`gemini-3.8-flash` cascade when `Hesitation >= 16%`) $\to$ **Stage 3** (file-based Human-in-the-Loop approval inside `/workspace/.agy/hitl/` resolved over `ax ssh <task>`), plus corresponding templates in `~/projects/ax-central/frontend/src/model/designer.ts`.

## Analysis

Seven fresh-context Goldfish subagents (`egm-design`, `egm-codebase-details`, `egm-zoom-out`, `egm-comprehension`, `egm-implementation-readiness`, `egm-structural`, and `egm-inventive-catalyst`) audited the hypothesis against `~/projects/dgem`, `~/projects/ax-experiments`, `~/projects/ax-central`, and `rakyll/ax-images`. Five primary technical contradictions and operational risks were identified and resolved:

1. **Hook Interception Split Between `ghcr.io/rakyll/ax-images/antigravity` (`run_shell`) and `agy` CLI (`run_command`)**:
   * *Contradiction*: `agy` CLI reads `/workspace/.agents/hooks.json` (`PreToolUse` matcher on `run_command`), whereas `ghcr.io/rakyll/ax-images/antigravity` (`cmd/antigravity/main.go`) executes `run_shell` directly in Go via `exec.CommandContext(ctx, "bash", "-lc", command)` (`internal/agent/tools.go:147`) and never reads `/workspace/.agents/hooks.json`. Furthermore, `dgem_gate.py:216` checks `if tool_name != "run_command": return None` in `evaluate_static_stage0()`.
   * *Resolution (Extraction + Normalization)*:
     1. Update `evaluate_static_stage0()` in `~/projects/dgem/examples/agy-safety-gate/dgem_gate.py` to accept `tool_name in ("run_command", "run_shell", "bash")`.
     2. For Surface A (`ghcr.io/rakyll/ax-images/antigravity`), set `BASH_ENV=/workspace/.agy/bash_gate.sh` in `Task.spec.env`. Because `internal/agent/tools.go:147` spawns `bash -lc <command>`, Bash sources `$BASH_ENV` with `$BASH_EXECUTION_STRING` set to the target command before executing it. `bash_gate.sh` immediately `unset BASH_ENV` (preventing recursion), runs `dgem_gate.py` on `$BASH_EXECUTION_STRING`, and exits `126` with the refusal message on `deny`.
   * *Secondary Trade-off*: `BASH_ENV` intercepts `bash -lc` invocations specifically; non-Bash direct `execve` calls (`read_file`, `write_file`, `edit_file`) remain workspace-scoped by `resolve(workspace, path)` in `internal/agent/tools.go`.
2. **Synchronous Headless Execution vs. Interactive Human Approval (`"ask"`) and Hook Timeouts**:
   * *Contradiction*: When the cascade (`Stage 0 -> Stage 1 dgem -> Stage 2 Gemini`) concludes with `escalate` (`agy_decision="ask"` for `state_or_remote_mutation`), returning `"ask"` inside a headless container with no attached TTY hangs or fails immediately, while the `15s` timeout in `hooks.example.json` kills the hook before a human operator can respond via `ax ssh`.
   * *Resolution (Inversion + File-Rendezvous Intermediary)*:
     1. When `decision == "escalate"` and `DGEM_GATE_HITL_DIR=/workspace/.agy/hitl` is set, `dgem_gate.py` writes `/workspace/.agy/hitl/<trace_id>.pending.json` (and symlinks `latest.pending.json`), emits an OTel span and stderr banner (`ax ssh <task> -- python3 /opt/dgem/agy-safety-gate/dgem_gate.py hitl-respond --decision allow|deny`), and polls `/workspace/.agy/hitl/<trace_id>.decision.json` every `250 ms` up to `DGEM_GATE_HITL_TIMEOUT` (default `60s`, failing closed to `deny` on expiration).
     2. Increase `.agents/hooks.json` `"timeout"` to `180` seconds when HITL mode is active, while keeping `dgem_gate.py`'s default behavior unchanged when `DGEM_GATE_HITL_DIR` is unset so existing local `agy` CLI unit tests pass without modification.
   * *Secondary Trade-off*: Holds the agent's turn open for up to `DGEM_GATE_HITL_TIMEOUT` seconds during human review.
3. **Substrate `32 KiB` `AX_WORKSPACE_YAML` Limit vs. `50.5 KiB` `dgem_gate.py`**:
   * *Contradiction*: Agent Substrate caps `AX_WORKSPACE_YAML` at `32,768` bytes (`internal/controller/reconciler.go:198`), whereas `~/projects/dgem/examples/agy-safety-gate/dgem_gate.py` is `50,467` bytes (`~49.3 KiB`). Inlining `dgem_gate.py` into `Workspace.spec.files` or an `ax-central` `designer.ts` template fails `ActorTemplate` creation on Kind + Agent Substrate with `ReasonTemplateCreationFailed`. Additionally, `dgem_gate.py:497` previously called `tmpl_path.read_text()` even in `gateway` mode, failing if `tool_safety_gate.json.tmpl` was not on the guest disk.
   * *Resolution (Segmentation + Server-Side Gateway Template Resolution)*:
     1. Update `call_dgem_stage1()` in `dgem_gate.py` so that in `gateway` mode, if the local `.json.tmpl` file is absent, it sends `"template": "tool_safety_gate"` (or `"calibration/agent_step_drift"`) to `POST ${DGEM_GATEWAY_URL}/api/decide`, which resolves the template server-side on `dgem serve`.
     2. For `ax-experiments/agy/` image builds (`dgem-genkit-task:latest`), copy `dgem_gate.py`, `sdk_demo.py`, and `templates/*.json.tmpl` from `${DGEM_REPO}` into `/opt/dgem/` inside the container image layer (zero `AX_WORKSPACE_YAML` overhead, zero repo copy-paste).
     3. For unmodified `ghcr.io/rakyll/ax-images/antigravity@sha256:8025a987...` and `ax-central` `designer.ts` templates, mount a compact `< 4 KiB` `/workspace/.agy/dgem_gate_lite.py` + `bash_gate.sh` + `.agents/hooks.json` in `Workspace.spec.files` (`< 6 KiB` total `AX_WORKSPACE_YAML`) that delegates Stage 1 + Stage 2 cascade to `POST ${DGEM_GATEWAY_URL}/api/decide`.
4. **Cross-Substrate Networking (`ate-local` `192.168.64.1:8095` vs. `Kind + Agent Substrate` `EgressPolicy`)**:
   * *Contradiction*: On macOS `ate-local`, microVMs dial `http://192.168.64.1:8095` over `vmnet`. On `Kind + Agent Substrate`, gVisor sandboxes enforce default-deny `EgressPolicy`, where `HttpRule.Hostnames` rejects raw IP literals (`192.168.64.1`, `172.18.0.1`), `TlsPassthroughRule` only allows port `443` (and single-label wildcards require `*.a.run.app`, not `*.run.app`), and `dgem serve` rejects `Host: host.docker.internal:8095` unless listed in `DGEM_ALLOWED_HOSTS`.
   * *Resolution*:
     1. In `dgem/ensure-stack.sh`, set `DGEM_ALLOWED_HOSTS="${DGEM_ALLOWED_HOSTS:-${DGEM_BRIDGE_HOST},host.docker.internal,host.containers.internal}"`.
     2. In `genkit/internal/axclient/client.go`, extend `EnsureActorEgressWithOptions` to attach both `TlsPassthroughRule` on port `443` (`*.googleapis.com`, `googleapis.com`, `*.a.run.app`, `github.com`, `*.githubusercontent.com`) and `HttpRule` on ports `8095`/`8080` (`host.docker.internal`, `host.containers.internal`) before `ax resume`.
5. **In-Sandbox Observability (`ax-central` `<ax-task-logs>` OTel Waterfall & Durable Audit Trail)**:
   * *Contradiction*: `internal/agent/tools.go:150` in `ax-images/antigravity` captures `run_shell` stdout/stderr into an internal buffer, hiding gate evaluations from `container logs -f` in `ax-central`, and `dgem_gate.py` previously did not persist `to_audit_record()` to `/workspace`.
   * *Resolution*: Add `_emit_container_otel_span()` to `dgem_gate.py` (writing `msg="genkit otel span"` lines to `/proc/1/fd/2` when writable so `<ax-task-logs>` renders Stage 0 / Stage 1 / Stage 2 / Stage 3 HITL spans in the OTel waterfall) and atomically append content-redacted `to_audit_record()` JSON lines to `DGEM_GATE_AUDIT_LOG` (`/workspace/.agy/audit.jsonl`).

## Goals vs. Non-Goals

* **In-Scope Goals:**
  * Provide **2 parameterized scripts** in `~/projects/ax-experiments/agy/`: `01-phase1-baseline.sh` (Phase 1 non-decision baseline) and `02-phase2-dgem-safety-gate.sh` (Phase 2 cascading `dgem` safety gate + `ax ssh` HITL), supporting `SUBSTRATE=atelocal|kind` and `SURFACE=ax-image|sdk`.
  * Source `dgem_gate.py`, `sdk_demo.py`, and `tool_safety_gate.json.tmpl` directly from `~/projects/dgem` (`DGEM_REPO`) without copy-pasting them into `ax-experiments`.
  * Verify `run_shell` / `run_command` Stage-0 matching, Stage-1 `dgem` 2-slot evaluation (`action_hazard` $\times$ `intent_origin`), `/proc/1/fd/2` OTel span emission, `/workspace/.agy/audit.jsonl` persistence, and `/workspace/.agy/hitl/` file-based HITL approval (`hitl-respond`) live inside AX sandboxes.
* **Out-of-Scope Non-Goals:**
  * Modifying the upstream `ghcr.io/rakyll/ax-images/antigravity` Go binary in `rakyll/ax-images` (all Surface A hooks work on the unmodified `sha256:8025a987...` image via `BASH_ENV` and `Workspace.spec.files`).
  * Building a background Unix socket daemon inside the sandbox for HITL approval (atomic file-based rendezvous in `/workspace/.agy/hitl/` requires zero background daemons and survives `/workspace` inspection).

## Alternatives Weighed

* **Maintaining 8 separate scripts for $2\text{ Surfaces} \times 2\text{ Substrates} \times 2\text{ Phases}$**: Rejected by author: creates high maintenance duplication across `vmnet` and `Kind` manifests; 2 phase scripts parameterized by `SUBSTRATE` and `SURFACE` cover all combinations cleanly.
* **Copy-pasting the 1,300-line `dgem_gate.py` into `ax-experiments/agy/` or inlining it into `Workspace.spec.files`**: Rejected by author: forks security-critical redirect/header invariants from `~/projects/dgem` and exceeds Agent Substrate's `32 KiB` `AX_WORKSPACE_YAML` limit (`50.5 KiB > 32 KiB`).
* **Returning raw `"decision": "ask"` to a headless container runner without an in-hook HITL rendezvous**: Rejected by author: headless container tasks have no attached interactive TTY, causing `"ask"` to either fail closed immediately or hang without notifying the operator how to approve over `ax ssh`.

## Key Decisions & Staging for Next Steps

1. **Repository 1 — `~/projects/dgem` (`examples/agy-safety-gate/dgem_gate.py`)**:
   * Normalize `tool_name` (`run_command`, `run_shell`, `bash`), support server-side `"template": "tool_safety_gate"` in `gateway` mode, emit OTel spans to `/proc/1/fd/2`, persist redacted audit records to `/workspace/.agy/audit.jsonl`, and add `DGEM_GATE_HITL_DIR` + `hitl-respond` / `hitl-list` CLI subcommands.
2. **Repository 2 — `~/projects/ax-experiments` (`agy/`, `okf/agy.md`, `dgem/ensure-stack.sh`, `genkit/internal/axclient/client.go`)**:
   * Create Track 2d (`agy/CONCEPTS_BRIEF.md`, `agy/README.md`, `agy/GUIDE.md`, `agy/01-phase1-baseline.sh`, `agy/02-phase2-dgem-safety-gate.sh`, `okf/agy.md`), plus add `egm-bootstrap` Peanuts `README.md` contracts for `genkit/cmd/a2a-mcp-bridge`, `genkit/cmd/egm-orchestrator`, and `genkit/internal/axclient`.
3. **Repository 3 — `~/projects/ax-central` (`ax-central-f90.2`)**:
   * Tracked in `bd` (`ax-central-f90.2`) for the `ax-central` agent to register the `"antigravity-dgem-gate"` Deploy preset and `<ax-task-logs>` HITL Approve/Deny action buttons.
