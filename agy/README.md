# Antigravity (`agy`) Coding Agents on AX with Cascading `dgem` Safety Gates (`agy`)

> **Open Knowledge Format (OKF) v0.2 Track Metadata & Lineage**: [`okf/agy.md`](../okf/agy.md) · **Bundle Index**: [`okf/index.md`](../okf/index.md) · **EGM Concepts Brief**: [`agy/CONCEPTS_BRIEF.md`](./CONCEPTS_BRIEF.md)

This experiment track runs **Google Antigravity (`agy`)** coding agents inside **AX** sandboxes across both Antigravity surfaces (**Surface A**: [`ghcr.io/rakyll/ax-images/antigravity`](https://github.com/rakyll/ax-images/tree/main/images/antigravity) and **Surface B**: the `agy` CLI `PreToolUse` hook & `google.antigravity` Python SDK) and both execution substrates (**Substrate 1**: macOS Apple `container` microVMs via `ate-local` and **Substrate 2**: Kubernetes `Kind + Agent Substrate` `runsc` gVisor sandboxes) in two phases:

1. **Phase 1 (`01-phase1-baseline.sh` — Non-Decision Baseline)**: Runs an un-gated Antigravity coding task (`GEMINI_API_KEY` only, zero `dgem` dependency) that inspects a repository, fixes a failing unit test, and writes `/workspace/agent-output.md`, while exposing how un-gated `run_shell` / `run_command` execution inside a sandbox is vulnerable to indirect prompt injection (`<untrusted_data>`) and `.env` secret exfiltration.
2. **Phase 2 (`02-phase2-dgem-safety-gate.sh` — Cascading `dgem` Safety Gate + `ax ssh` HITL)**: Protects every tool call with a 4-tier cascading policy engine backed by [`~/projects/dgem/examples/agy-safety-gate/dgem_gate.py`](https://github.com/GoogleCloudPlatform/dgem) and `templates/tool_safety_gate.json.tmpl` (`action_hazard` $\times$ `intent_origin`).

---

## Surface $\times$ Phase Architecture Matrix

| Dimension | Surface A: Turnkey Image (`ghcr.io/rakyll/ax-images/antigravity@sha256:8025a987...`) | Surface B: `agy` CLI & Python SDK (`google.antigravity` / `dgem_gate.py`) |
|---|---|---|
| **Agent Loop** | Go binary (`/usr/local/bin/ax-agent`) calling the Gemini Interactions API (`client.Interactions` with `agent: "antigravity-preview-09-2026"`), executing `run_shell`, `read_file`, `write_file`, and `edit_file` locally in `/workspace`. | `agy` CLI (`.agents/hooks.json` `PreToolUse` command hook on `stdin`/`stdout`) and `google.antigravity` Python SDK (`@hooks.pre_tool_call_decide` and `policy.ask_user("run_command", handler=...)`). |
| **Phase 1 (Baseline)** | Runs `Task.spec.config.prompt` with no `PreToolUse` gate; `run_shell` (`bash -lc <cmd>`) executes all commands without approval. | Runs tool calls without `dgem_gate.py`; planted `<untrusted_data>` commands in logs/files execute unchecked. |
| **Phase 2 (`dgem` Gate)** | Sets `BASH_ENV=/workspace/.agy/bash_gate.sh` in `Task.spec.env`, which intercepts every `bash -lc <cmd>` spawned by `run_shell`, unsets `BASH_ENV` to prevent recursion, evaluates `$BASH_EXECUTION_STRING` through `dgem_gate.py`, and exits `126` on `deny`. | Registers `.agents/hooks.json` (`timeout: 180`) and SDK callbacks calling `dgem_gate.py` (`Stage 0 static -> Stage 1 dgem 2-slot -> Stage 2 Gemini -> Stage 3 file HITL over ax ssh`). |

---

## Substrate Environment & Networking Reference

| Substrate | Sandbox Runtime | Image Reference Format | `DGEM_GATEWAY_URL` | Egress & Host-Header Configuration |
|---|---|---|---|---|
| **macOS `ate-local`** (`SUBSTRATE=atelocal`) | Apple `container` Linux `aarch64` microVM (`192.168.64.x`) | Local tags (`ax-agent-local:latest`, `dgem-genkit-task:latest`) or `@sha256:` digests | `http://192.168.64.1:8095` | Host `dgem serve` runs with `DGEM_GATEWAY_HOST=0.0.0.0` and `DGEM_ALLOWED_HOSTS=192.168.64.1,host.docker.internal,host.containers.internal` (configured automatically by `dgem/ensure-stack.sh`). |
| **`Kind + Agent Substrate`** (`SUBSTRATE=kind`) | `runsc` (gVisor) sandbox pod | Must be pinned by `@sha256:` digest (`ghcr.io/.../antigravity@sha256:...` or `localhost:5001/...`) | `http://host.docker.internal:8095` or `https://<cloud-run>.a.run.app` | Requires `EnsureActorEgressWithOptions` (`genkit/internal/axclient/client.go`) attaching `TlsPassthroughRule:443` (`*.googleapis.com`, `*.a.run.app`, `github.com`) and `HttpRule:8095` (`host.docker.internal`). |

---

## Contents of This Folder

| File | Purpose |
|---|---|
| [`CONCEPTS_BRIEF.md`](./CONCEPTS_BRIEF.md) | 7-lens EGM Goldfish brainstorm brief and contradiction resolutions. |
| [`GUIDE.md`](./GUIDE.md) | Full architectural walkthrough, 4-stage policy cascade reference, `ax ssh` HITL operator guide, and empirical results from live microVM runs. |
| [`01-phase1-baseline.sh`](./01-phase1-baseline.sh) | **Phase 1 (`make agy-01`)**: Non-decision baseline coding agent on AX (`SUBSTRATE=atelocal\|kind`, `SURFACE=sdk\|ax-image`). |
| [`02-phase2-dgem-safety-gate.sh`](./02-phase2-dgem-safety-gate.sh) | **Phase 2 (`make agy-02`)**: Cascading `dgem` 2-slot `PreToolUse` safety gate (`Stage 0 static -> Stage 1 dgem -> Stage 2 Gemini -> Stage 3 file HITL over ax ssh`) + `/workspace/.agy/audit.jsonl` verification. |

---

## Quickstart

```bash
cd ~/projects/ax-experiments

# Phase 1: Non-decision baseline coding agent (no dgem server required)
make agy-01

# Phase 2: Cascading dgem 2-slot PreToolUse safety gate + live ax ssh HITL approval
make agy-02

# Optional: Run Phase 1 with the upstream ghcr.io/rakyll/ax-images/antigravity image
GEMINI_API_KEY="your-key" SURFACE=ax-image ./agy/01-phase1-baseline.sh
```

See [`GUIDE.md`](./GUIDE.md) for the full walkthrough and recorded outputs.
