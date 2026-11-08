# Declarative, Suspendable AI Agents on AX with Genkit Go

This two-part guide introduces **AX** (`ax.io/v1alpha1`), shows how **Genkit Go** maps onto sandboxed agent tasks, and walks through running `genkit-runner`:

- **Part 1 (Local on Crostini / Linux)**: Build `genkit-runner` and test the full lifecycle on a local machine. You will configure an agent declaratively in `Task.spec.config` using Dotprompt, run workspace filesystem tools, call both the A2A JSON-RPC and Genkit HTTP endpoints, and verify that session snapshots survive a simulated suspend/resume restart.
- **Part 2 (Cluster E2E on GCE with Agent Substrate)**: Deploy AX and Agent Substrate on a single Ubuntu 24.04 GCE VM to exercise scale-to-zero (`ax suspend`), wake-on-request through `atenet-router`, and multi-turn incident triage.

---

## Background: AX and Genkit Go

### AX in 60 Seconds

[AX](https://github.com/google/ax) is a declarative, Kubernetes-shaped orchestrator for running sandboxed AI agent tasks on [Agent Substrate](https://github.com/agent-substrate/substrate). It defines three core resources (`ax.io/v1alpha1`):

1. **`Workspace`**: Declares the repositories (`spec.git`), inline files (`spec.files`), skills (`spec.skills`), and MCP servers (`spec.mcp`) an agent uses.
2. **`Task`**: Binds a container image (`spec.image`), a `Workspace` (`spec.workspace`), resource limits, and a runner configuration object (`spec.config`) into a sandboxed Substrate **Actor**.
3. **`Model`**: Declares model provider configurations and credential references.

Every AX Task runs inside a sandbox with a **runner** as PID 1 (`/usr/local/bin/ax-task-runner`). The runner:
- Materializes the bound `Workspace` into `/workspace` once on its initial boot, and skips re-cloning on later resumes so the agent's files stay intact.
- Serves `/healthz` and `/readyz` on port 80 (used by AX and Substrate's `atenet-router` wakeup probe), plus optional `h2c` gRPC guest services when `spec.debug: true` (which back `ax ssh`).
- Serves `/metadata/v1alpha1/ax/task` and `/metadata/v1alpha1/ax/workspace` on loopback (`127.0.0.1:8099`, exposed via `AX_METADATA_URL`).

### How `genkit-runner` Turns a Task Manifest into an Agent Server

Before `genkit-runner` ([google/ax#538](https://github.com/google/ax/issues/538)), running an interactive or server-backed agent on AX required building a custom container image, writing agent entrypoint code, and setting `spec.command`. With `cmd/runners/genkit-runner`, the `Task` YAML manifest defines the whole agent:

1. **Single Static Go Binary**: AX is written in Go. `genkit-runner` embeds AX's `runner` package and Genkit Go (`github.com/firebase/genkit/go@v1.14.0`) in one binary with no secondary language runtime.
2. **Declarative Agent Authoring via Dotprompt (`spec.config`)**: Genkit defines a declarative schema for models, generation parameters, tool loops (`maxTurns`), input/output schemas, and middleware (`use`): [Dotprompt](https://genkit.dev/docs/go/dotprompt/). Users write standard Dotprompt frontmatter plus `instruction` under `Task.spec.config`.
3. **Session Durability Across Suspend/Resume**: Agent Substrate snapshots the `/workspace` volume when a task suspends (`SNAPSHOT_FIDELITY_VOLUMES`) and restores it into a fresh container on resume. `genkit-runner` backs every agent with Genkit's `localstore.NewFileSessionStore` rooted at `/workspace/.genkit/snapshots`. Each turn is atomically `fsync`-written to disk, so multi-turn conversations survive `ax suspend` and `ax resume` without extra configuration.
4. **Workspace Integration (Filesystem, Skills, MCP)**:
   - **Filesystem**: Genkit's `genkit-middleware/filesystem` provides `list_files`, `read_file`, `write_file`, and `search_and_replace` confined to `/workspace` via Go's `os.Root`.
   - **Skills**: `genkit-middleware/skills` discovers `SKILL.md` files in the Workspace's `spec.skills.path` (`.agents/skills`).
   - **MCP**: At startup, `genkit-runner` connects `mcp.NewGenkitMCPClient` to every MCP server in `Workspace.spec.mcp` (`Stdio` or `StreamableHTTP`) and registers its tools on the agent.
5. **Dual Protocol Serving on Port 80 (A2A + Genkit Native HTTP)**:
   - **A2A JSON-RPC** (`POST /` and `GET /.well-known/agent-card.json`) via `github.com/a2aproject/a2a-go/v2`, so any A2A client or orchestrator can message the task through `atenet-router`.
   - **Genkit Native Agent HTTP Routes** (`POST /agents/<name>`, `/getSnapshot`, `/waitForSnapshot`, `/abort`), supporting SSE streaming (`?stream=true`), detached background execution, and Vercel AI SDK UI (`@genkit-ai/vercel-ai`).

---

## Part 1: Testing `genkit-runner` Locally on a Chromebook with Debian Linux (No Docker or Kubernetes Required)

`genkit-runner` accepts `--task-file`, `--workspace-file`, `--ax-dir`, and `--port` flags so you can run the in-container lifecycle directly on a Crostini Linux VM.

### Authentication Options: Vertex AI ADC vs. `GEMINI_API_KEY`

Genkit Go supports two ways to authenticate with Gemini models, selected by the model prefix in `spec.config.model`:

- **`vertexai/gemini-4-argon` (Google Cloud Application Default Credentials)**: Uses your local `gcloud auth application-default login` credentials and `GOOGLE_CLOUD_PROJECT` environment variable (`GOOGLE_CLOUD_LOCATION` defaults to `global`). No `GEMINI_API_KEY` is needed.
- **`googleai/gemini-4-argon` (or bare `gemini-4-argon`)**: Uses the Google AI Gemini Developer API and reads `GEMINI_API_KEY` (or `GOOGLE_API_KEY`) from the environment or `Task.spec.env`.

In our test below, we use `vertexai/gemini-4-argon` with Application Default Credentials (`GOOGLE_CLOUD_PROJECT` already set in the shell).

### Step 1: Build `genkit-runner`

From your `ax` repository checkout on the `feat/genkit-runner` branch:

```bash
cd ~/projects/ax
go build -o bin/genkit-runner ./cmd/runners/genkit-runner
```

### Step 2: Inspect the Sample `Workspace` and `Task` Manifests

In `~/projects/ax-experiments/genkit/`, two manifests set up a codebase triage task:

**`workspace.yaml`** — Materializes a mock Go payment service (`README.md` and a buggy `retry_test.go`), a runbook skill (`.agents/skills/incident-runbook/SKILL.md`), and a zero-dependency Python stdio MCP server (`tools/incident_mcp.py`):

```yaml
apiVersion: ax.io/v1alpha1
kind: Workspace
metadata:
  name: demo-workspace
  atespace: default
spec:
  files:
    - path: "README.md"
      content: |
        # Payment Service (payd)
        Handles checkout authorization and settlement retries.

        ## Known Issues
        - `TestRetryBackoff_ZeroJitter` in `retry_test.go` fails intermittently when `maxJitter == 0` because `rand.Int63n(0)` panics.
        - `settlement.go`: batch timeout is hardcoded to 5s instead of reading `Config.BatchTimeout`.
    - path: "retry_test.go"
      content: |
        package payd

        import (
            "math/rand"
            "testing"
        )

        func ComputeJitter(maxJitter int64) int64 {
            // BUG: panics when maxJitter <= 0
            return rand.Int63n(maxJitter)
        }

        func TestRetryBackoff_ZeroJitter(t *testing.T) {
            got := ComputeJitter(0)
            if got != 0 {
                t.Fatalf("ComputeJitter(0) = %d, want 0", got)
            }
        }
    - path: ".agents/skills/incident-runbook/SKILL.md"
      content: |
        ---
        name: incident-runbook
        description: Standard operating procedure for triaging payd incidents and formatting triage reports.
        ---
        # Payment Service (payd) Incident Runbook
        1. Inspect `README.md` and the failing test file before editing any code.
        2. Keep code fixes minimal and guard against zero or negative bounds.
        3. Write a concise summary to `TRIAGE_REPORT.md`.
    - path: "tools/incident_mcp.py"
      content: |
        #!/usr/bin/env python3
        # Minimal zero-dependency stdio MCP server exposing get_active_incident
        ...
  mcp:
    servers:
      - name: telemetry
        command: "python3"
        args: ["/workspace/tools/incident_mcp.py"]
  skills:
    path: ".agents/skills"
```

**`task.yaml`** — Defines `triage_agent` using `vertexai/gemini-4-argon` and enables `genkit-middleware/filesystem` with write access:

```yaml
apiVersion: ax.io/v1alpha1
kind: Task
metadata:
  name: genkit-triage
  atespace: default
spec:
  image: "localhost:5001/genkit-runner@sha256:REPLACE_WITH_PUSHED_DIGEST"
  config:
    name: triage_agent
    description: Triages failing tests and writes reports to the workspace.
    model: vertexai/gemini-4-argon
    instruction: |
      You are a careful Go engineer triaging a repository in your workspace.
      Always use the filesystem tools (list_files, read_file, write_file,
      search_and_replace) to inspect files before answering or making changes.
      Keep your answers concise.
    config:
      maxOutputTokens: 2048
      temperature: 0.2
    maxTurns: 10
    use:
      - name: genkit-middleware/filesystem
        config:
          allowWriteAccess: true
      - name: genkit-middleware/skills
  workspace:
    name: demo-workspace
    path: "/home/hussain/projects/ax-experiments/genkit/sandbox-workspace"
  debug: true
```

### Step 3: Boot 1 — Initial Workspace Setup & First A2A Turn

Start `genkit-runner` on port `18080`:

```bash
rm -rf ~/projects/ax-experiments/genkit/sandbox-workspace ~/projects/ax-experiments/genkit/ax-state

~/projects/ax/bin/genkit-runner \
  --task-file ~/projects/ax-experiments/genkit/task.yaml \
  --workspace-file ~/projects/ax-experiments/genkit/workspace.yaml \
  --ax-dir ~/projects/ax-experiments/genkit/ax-state \
  --port 18080 \
  --metadata-port 18099
```

**Runner startup log (Boot 1):**

```text
level=INFO msg="initializing AX task runner" port=18080 workspace=demo-workspace wsPath=/home/hussain/projects/ax-experiments/genkit/sandbox-workspace
level=INFO msg="guest services enabled (spec.debug is true)"
level=INFO msg="probe and guest server started" addr=[::]:18080
level=INFO msg="metadata server started" addr=127.0.0.1:18099
level=INFO msg="executing workspace maiden run setup" path=/home/hussain/projects/ax-experiments/genkit/sandbox-workspace
level=INFO msg="wrote inlined workspace file" path=/home/hussain/projects/ax-experiments/genkit/sandbox-workspace/README.md
level=INFO msg="wrote inlined workspace file" path=/home/hussain/projects/ax-experiments/genkit/sandbox-workspace/retry_test.go
level=INFO msg="maiden run workspace setup completed successfully" path=/home/hussain/projects/ax-experiments/genkit/sandbox-workspace
level=INFO msg="Genkit initialized" env=prod plugins="[genkit-middleware vertexai]" duration=5ms
level=INFO msg="initialized Genkit agent server" agent=triage_agent model=vertexai/gemini-4-argon storeDir=/home/hussain/projects/ax-experiments/genkit/sandbox-workspace/.genkit/snapshots mcpTools=0
level=INFO msg="workspace maiden run setup marked ready" path=/home/hussain/projects/ax-experiments/genkit/sandbox-workspace
level=INFO msg="no task command specified; serving metadata until stopped"
```

In a second terminal, check the readiness probe and the A2A Agent Card:

```bash
curl -s http://127.0.0.1:18080/readyz
# ok

curl -s http://127.0.0.1:18080/.well-known/agent-card.json | jq .
```

```json
{
  "supportedInterfaces": null,
  "capabilities": {},
  "defaultInputModes": [
    "text/plain"
  ],
  "defaultOutputModes": [
    "text/plain"
  ],
  "description": "Triages failing tests and writes reports to the workspace.",
  "name": "triage_agent",
  "skills": null,
  "version": "1.0.0"
}
```

Send an A2A `message/send` JSON-RPC request with `"contextId": "incident-42"` asking the agent to inspect the workspace, fix the bug in `retry_test.go`, and write `TRIAGE_REPORT.md`:

```bash
curl -s -H "Content-Type: application/json" http://127.0.0.1:18080/ -d '{
  "jsonrpc": "2.0", "id": 1, "method": "message/send",
  "params": {"message": {"role": "user", "messageId": "m1", "contextId": "incident-42",
    "parts": [{"kind": "text", "text": "Inspect the workspace files, fix the bug in retry_test.go, and write a brief summary to TRIAGE_REPORT.md."}]}}
}' | jq .
```

**Actual Output (`gemini-4-argon`):**

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "kind": "message",
    "messageId": "01a19023-30d8-75a8-a5ab-014267a9afae",
    "contextId": "incident-42",
    "parts": [
      {
        "kind": "text",
        "text": "I have inspected the workspace, fixed the bug in `retry_test.go`, and written the summary to `TRIAGE_REPORT.md`:\n\n- **`retry_test.go`**: Updated `ComputeJitter` to return `0` when `maxJitter <= 0`, preventing `rand.Int63n` from panicking on zero or negative input in `TestRetryBackoff_ZeroJitter`.\n- **`TRIAGE_REPORT.md`**: Documented the fix in `retry_test.go` and noted the remaining issue mentioned in `README.md` regarding `settlement.go`."
      }
    ],
    "role": "agent",
    "taskId": "01a19022-e732-7123-b105-57e1288b84f0"
  }
}
```

Inspecting `sandbox-workspace/retry_test.go` and `sandbox-workspace/TRIAGE_REPORT.md` confirms the agent called `search_and_replace` and `write_file` to patch the code and write the report:

```go
func ComputeJitter(maxJitter int64) int64 {
    if maxJitter <= 0 {
        return 0
    }
    return rand.Int63n(maxJitter)
}
```

```markdown
# Triage Report

## Summary
- **Issue Fixed (`retry_test.go`)**: `ComputeJitter` previously called `rand.Int63n(maxJitter)` unconditionally, which panics when `maxJitter <= 0` (such as in `TestRetryBackoff_ZeroJitter`). Added a guard to return `0` when `maxJitter <= 0`.
- **Other Findings (`README.md`)**: `README.md` notes a known issue in `settlement.go` (hardcoded 5s batch timeout instead of using `Config.BatchTimeout`), though `settlement.go` is not currently present in the workspace.
```

### Step 4: Simulate `ax suspend` and `ax resume` (Boot 2)

Stop the `genkit-runner` process (`Ctrl+C` / `SIGTERM`), which simulates `ax suspend` stopping the container and snapshotting `/workspace`.

Now start a fresh `genkit-runner` process pointed at the same workspace directory:

```bash
~/projects/ax/bin/genkit-runner \
  --task-file ~/projects/ax-experiments/genkit/task.yaml \
  --workspace-file ~/projects/ax-experiments/genkit/workspace.yaml \
  --ax-dir ~/projects/ax-experiments/genkit/ax-state \
  --port 18080 \
  --metadata-port 18099
```

The runner sees the initialization marker under `ax-state/` and skips maiden-run setup, leaving the agent's edits in `sandbox-workspace/` intact:

```text
level=INFO msg="workspace already initialized; skipping maiden run setup" path=/home/hussain/projects/ax-experiments/genkit/sandbox-workspace
```

Send a follow-up A2A message carrying the same `"contextId": "incident-42"`, and instruct it not to read any files so it answers from the persisted snapshot on disk:

```bash
curl -s -H "Content-Type: application/json" http://127.0.0.1:18080/ -d '{
  "jsonrpc": "2.0", "id": 2, "method": "message/send",
  "params": {"message": {"role": "user", "messageId": "m2", "contextId": "incident-42",
    "parts": [{"kind": "text", "text": "Without reading any files again, what file did you fix in our previous turn and what was the second known issue mentioned in README.md?"}]}}
}' | jq .
```

**Actual Output (`gemini-4-argon`):**

```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "result": {
    "kind": "message",
    "messageId": "01a19023-bdfe-7719-88ca-548ba5919dd8",
    "contextId": "incident-42",
    "parts": [
      {
        "kind": "text",
        "text": "- **File fixed**: `retry_test.go`\n- **Second known issue in `README.md`**: In `settlement.go`, the batch timeout is hardcoded to `5s` instead of reading `Config.BatchTimeout`."
      }
    ],
    "role": "agent",
    "taskId": "01a19023-ae2e-74ad-a39e-6588db58ab6b"
  }
}
```

Next, call Genkit's native HTTP endpoint (`POST /agents/triage_agent`) on the same session ID `"incident-42"`:

```bash
curl -s -H "Content-Type: application/json" http://127.0.0.1:18080/agents/triage_agent -d '{
  "data": {"message": {"role": "user", "content": [{"text": "Reply in one sentence confirming how many user messages we have sent in this session."}]}},
  "init": {"sessionId": "incident-42"}
}' | jq .
```

```json
{
  "result": {
    "finishReason": "stop",
    "message": {
      "content": [
        {
          "text": "You have sent 3 conversational user prompts in this session (or 4 total user-role messages if counting the intermediate `<read_file>` delivery message)."
        }
      ],
      "role": "model"
    },
    "sessionId": "incident-42",
    "snapshotId": "89df7b78-7757-4a5c-8dc6-9fc089a21e84",
    "usage": {
      "inputCharacters": 1952,
      "inputTokens": 2106,
      "outputCharacters": 152,
      "outputTokens": 36,
      "thoughtsTokens": 111,
      "totalTokens": 2253
    }
  }
}
```

---

## Part 2: Cluster E2E Scenario on a GCE VM (Agent Substrate + Wake-on-Request)

Part 1 exercises `genkit-runner` in a single local process. Running **AX + Agent Substrate + Genkit** in a cluster adds sandbox isolation, volume checkpointing, and on-demand wake-up.

### The Scenario: Zero-Idle Incident Responder

Consider an organization running dozens of repo-specialized triage or incident-response agents, one per microservice repository, each with its code cloned in `/workspace`, its team's runbooks in `.agents/skills/`, and its telemetry connected via `Workspace.spec.mcp`. Keeping dozens of agent containers and cloned workspaces running idle 24/7 wastes CPU and memory.

On **AX + Agent Substrate**, the lifecycle works as follows:
1. **Apply & Golden Snapshot (`Suspended` by default)**: Run `ax apply -f genkit/workspace.yaml -f genkit/task.yaml`. The task starts in the `Suspended` phase (`workerIP: ""`), consuming zero worker CPU or memory.
2. **First Wake-up & Bootstrap Setup**: A PagerDuty webhook or developer sends an A2A `message/send` request to `http://atenet-router.ate-system.svc.cluster.local/` with header `ate-target-actor: default/genkit-triage`. The `atenet-router` wakes the suspended actor, waits for `/readyz` to return `200 OK` (after workspace setup, MCP handshake, and Genkit initialization finish), and forwards the A2A request.
3. **Tool Use & Durable State**: The Genkit agent loads the `incident-runbook` skill via `use_skill`, calls the `telemetry_get_active_incident` MCP tool, edits `retry_test.go` in `/workspace`, and writes its session snapshot to `/workspace/.genkit/snapshots`.
4. **Scale-to-Zero Between Turns (`ax suspend`)**: While waiting for human review or CI results, the task suspends (`ax suspend task genkit-triage`). Substrate snapshots `/workspace` (capturing both the modified code and `.genkit/snapshots`) and tears down the worker pod.
5. **Wake-on-Request Continuity**: Hours later, a follow-up A2A message arrives at `atenet-router` with `ate-target-actor: default/genkit-triage` and the same `contextId`. The router resumes the actor onto a worker, restores `/workspace`, waits for `/readyz`, and delivers the message. The Genkit agent continues the conversation at turn 2 with both its chat history and its uncommitted file changes intact.

### Components of AX and Agent Substrate Tested in Part 2

| Component | Behavior Under Test | Verification Command |
|---|---|---|
| **1. ActorTemplate & Digest Pinning** | AX creates `<task>-tmpl-<hash>` with `WakeupProbe: GET /readyz:80` and `SNAPSHOT_FIDELITY_VOLUMES`. | `ax describe task genkit-triage` |
| **2. Workspace Materialization** | `spec.git` clones a repository into `/workspace`, `spec.files` writes `.agents/skills/incident-runbook/SKILL.md` and `tools/incident_mcp.py`, and `spec.mcp` declares the stdio server. | `ax ssh genkit-triage -- ls -la /workspace` |
| **3. `atenet-router` Wake-on-Request** | Sending an HTTP request with `ate-target-actor: default/genkit-triage` while the task is `Suspended` wakes the actor and holds the request until `/readyz` returns `200`. | Send `curl` while `ax get task` shows `Suspended`; confirm the task moves to `Running` and returns the A2A reply. |
| **4. `ax suspend` & Volume Checkpointing** | Suspending releases the worker (`workerIP` becomes empty) and snapshots `/workspace` while discarding rootfs (`/tmp`). | Write `/tmp/ephemeral` before `ax suspend`; after resume, verify `/tmp/ephemeral` is gone while `/workspace` files and `.genkit/snapshots` remain. |
| **5. Guest Exec (`ax ssh`)** | Multiplexed `h2c` gRPC guest services run on port 80 alongside the Genkit HTTP/A2A server when `spec.debug: true`. | `ax ssh genkit-triage -- cat /workspace/TRIAGE_REPORT.md` |

### Genkit Go Primitives Active in the Workspace

- **Workspace MCP Server (`Workspace.spec.mcp` + `plugins/mcp`)**: `genkit/workspace.yaml` drops a zero-dependency Python stdio MCP server at `/workspace/tools/incident_mcp.py` and registers it under `spec.mcp.servers` (`name: telemetry`). On startup, `genkit-runner` connects `mcp.NewGenkitMCPClient` over stdio and exposes `telemetry_get_active_incident` to the model.
- **Workspace Skills (`Workspace.spec.skills` + `genkit-middleware/skills`)**: `genkit/workspace.yaml` writes `.agents/skills/incident-runbook/SKILL.md`. `genkit-middleware/skills` scans `.agents/skills`, injects the skill catalog into the system prompt, and registers the `use_skill` tool so the model can load the runbook on demand.
- **Scoped Filesystem Tools (`genkit-middleware/filesystem`)**: Confines `list_files`, `read_file`, `write_file`, and `search_and_replace` to `/workspace` using Go's `os.Root`.
- **Durable Session Store (`localstore.NewFileSessionStore`)**: Persists `<prefix>/<snapshotID>.json` (full message transcript, tool calls, and token usage) plus `<prefix>/.pointers/<sessionID>.json` (mapping the A2A `contextId` or Genkit `sessionId` to the latest snapshot) inside `/workspace/.genkit/snapshots`.

### Broader Scenarios for AX + Genkit Go

1. **Scale-to-Zero Interactive Coding & Triage Agents ([google/ax#501](https://github.com/google/ax/issues/501), [#537](https://github.com/google/ax/issues/537), [#538](https://github.com/google/ax/issues/538))**: Per-incident or per-PR agents sit behind `atenet-router` at zero cost when idle, wake up when a webhook or engineer sends a message, and keep their working tree and conversation state across days.
2. **Parallel Fleet Sweeps ([google/ax#513](https://github.com/google/ax/pull/513))**: Spinning up hundreds of isolated sandboxes in parallel across a fleet of repositories for dependency migrations, flaky test fixes, or security audits.
3. **Multi-Agent A2A Topologies (`genkitx.DefineRemoteAgent`)**: Because every AX Task is addressable inside the cluster at `http://atenet-router.ate-system.svc.cluster.local` via `ate-target-actor: <atespace>/<task>`, a coordinator agent can delegate work to specialist tasks (`default/db-analyst`, `default/security-reviewer`, `default/test-fixer`) over A2A or Genkit's `DefineRemoteAgent`, waking each specialist only when called.
4. **Multi-Tenant Sandboxes with Egress Credential Injection ([google/ax#475](https://github.com/google/ax/issues/475), [#516](https://github.com/google/ax/issues/516))**: Isolating tasks per tenant (`atespace`) while keeping raw API keys and Git tokens out of the container environment via Substrate's egress gateway.

### Provisioning the GCE VM with `genkit/bootstrap-gce.sh`

A single **Ubuntu 24.04 LTS** GCE VM is the simplest environment for this end-to-end test: Ubuntu 24.04 ships with Linux kernel **6.8** (required by Substrate's OverlayFS `lowerdir+` image cache), and `genkit/bootstrap-gce.sh` automates installing Docker, Kind, `kubectl`, Go, Agent Substrate (`v0.6.0`), AX, and the `genkit-runner` image on first boot.

```bash
# 1. Create an Ubuntu 24.04 LTS VM (8 vCPU, 32 GB RAM, 100 GB disk) with the startup script
gcloud compute instances create ax-genkit-e2e \
  --machine-type=n2-standard-8 \
  --image-family=ubuntu-2404-lts-amd64 \
  --image-project=ubuntu-os-cloud \
  --boot-disk-size=100GB \
  --boot-disk-type=pd-balanced \
  --scopes=cloud-platform \
  --metadata-from-file=startup-script=genkit/bootstrap-gce.sh

# 2. Follow the bootstrap log over SSH until it prints "Bootstrap complete!"
gcloud compute ssh ax-genkit-e2e --command="tail -f /var/log/ax-genkit-bootstrap.log"

# 3. (Optional) Save a reusable GCE custom image with pre-built Substrate images cached in /var/cache/substrate-registry
gcloud compute images create ax-substrate-v0-6-0-ubuntu2404 \
  --source-disk=ax-genkit-e2e \
  --source-disk-zone=$(gcloud config get-value compute/zone)
```

---

## Part 3: Full-Stack MicroVM Verification on macOS with `ate-local` & Apple `container`

On Apple Silicon macOS, you can exercise the complete **`ax` CLI + `ax-server` + `ate-local` + `genkit-runner`** lifecycle inside a real Linux microVM (`container` 1.0) in ~3 seconds—without spinning up a GCE VM or Kind cluster.

Because the microVM mounts the workspace at `/workspace`, the Python stdio MCP server (`tools/incident_mcp.py` in `genkit/workspace.yaml`) connects automatically at `/workspace/tools/incident_mcp.py` (`mcpTools=1`), and the container's `vmnet` bridge IP (`192.168.64.x:80`) exposes the A2A and Genkit HTTP routes directly to your Mac.

### Running the Automated E2E Script (`genkit/run-apple-container.sh`)

```bash
# 1. Start the local AX + ate-local stack in ~/projects/ax (feat/ate-local-apple-container)
cd ~/projects/ax
make local-up
source .ax-local/env

# 2. Run the Genkit microVM lifecycle test
cd ~/projects/ax-experiments
export GEMINI_API_KEY="AIzaSy..."
./genkit/run-apple-container.sh
```

**Verified MicroVM Output (`googleai/gemini-3.8-flash`):**

1. **Turn 1 (A2A JSON-RPC on `192.168.64.220:80`, `contextId: "incident-42"`) — Calls `telemetry_get_active_incident` over MCP, fixes `retry_test.go`, and writes `TRIAGE_REPORT.md`:**
   ```json
   {
     "jsonrpc": "2.0",
     "id": 1,
     "result": {
       "kind": "message",
       "contextId": "incident-42",
       "parts": [
         {
           "kind": "text",
           "text": "### Active Incident\n- **ID & Severity:** INC-2026-1030 (SEV-2)\n- **Error:** `panic: invalid argument to Int63n in payd.ComputeJitter`\n\n### Resolution\n- **Fixed `retry_test.go`:** Added a guard in `ComputeJitter` to return `0` when `maxJitter <= 0`, preventing invalid arguments to `rand.Int63n`.\n- **Created `TRIAGE_REPORT.md`:** Documented the fix in `## Summary` and noted the unaddressed `settlement.go` hardcoded batch timeout under `## Remaining Risks`."
         }
       ],
       "role": "agent"
     }
   }
   ```
2. **Real `ax suspend` → `ax resume` (Stops microVM at `.220` and cold-boots fresh microVM at `.221` with `/workspace/.genkit/snapshots` preserved):**
   - **Turn 2 (A2A JSON-RPC on `192.168.64.221:80`)**: Recalls the fixed file (`retry_test.go`) and remaining risk (`settlement.go`) directly from the restored session snapshot without reading files.
   - **Turn 3 (Genkit HTTP `POST http://192.168.64.221:80/agents/triage_agent`, `sessionId: "incident-42"`)**: Confirms all 3 user turns across the microVM suspend/resume cycle.

---

## Part 4: Multi-Agent Genkit Examples on Agent Substrate (`01-egm-review-panel.sh` & `02-in-cluster-delegation.sh`)

Beyond single-task triage, `genkit/` includes two multi-agent examples designed using the **[Elephant-Goldfish Model (EGM)](./CONCEPTS_BRIEF.md)** and verified on a local Kind + Agent Substrate (`v1.0.0-rc.1`) cluster over the **A2A gRPC transport (`lf.a2a.v1.A2AService/SendStreamingMessage`)**:

### Example 01: Sandboxed Elephant-Goldfish Design & Review Loop (`./genkit/01-egm-review-panel.sh`)

Demonstrates stateful vs. stateless context isolation across 4 `genkit-runner` tasks on a 3-worker gVisor pool (`1m 10.95s` total):

1. **Elephant Turn 1 (`5.87s`)**: `elephant-architect` (`allowWriteAccess: true`, `contextId: "elephant-session-1"`) reads `CONTEXT.md` and drafts `/workspace/DESIGN_SPEC.md` over A2A gRPC `SendStreamingMessage`.
2. **Residency Inversion (`ax suspend task elephant-architect`)**: Frees the Elephant's gVisor worker slot before dispatching the 3-way review wave.
3. **3-Way Parallel Goldfish Wave (`10.58s` / `12.60s` / `15.45s`)**:
   - `goldfish-design`, `goldfish-catalyst`, and `goldfish-comprehension` (`allowWriteAccess: false`) mount reviewer skills from `~/projects/elephant-goldfish-model/agents/*.md` at `.agents/skills/<persona>/SKILL.md` and declare a Dotprompt Picoschema `output.schema` (`reviewer`, `verdict`, `summary`, `findings`).
   - All 3 Goldfish tasks wake concurrently across the 3 gVisor workers, stream structured JSON findings over A2A gRPC `SendStreamingMessage` with wave-scoped `contextId` (`wave-1-goldfish-...`), and immediately suspend (`ax suspend`) back to zero compute.
4. **Elephant Turn 2 (`28.53s` including wake-on-request + RustFS restore)**:
   - `atenet-router` wakes `elephant-architect` on demand (`contextId: "elephant-session-1"`), restores its Turn 1 session snapshot, updates `/workspace/DESIGN_SPEC.md`, and writes `/workspace/RESOLUTION_LOG.md`.

### Example 02: Autonomous In-Cluster Agent-to-Agent Delegation (`./genkit/02-in-cluster-delegation.sh`)

Demonstrates true autonomous in-sandbox delegation without a host relay (`45.14s` total; `18.89s` coordinator turn):

1. **In-Sandbox A2A gRPC MCP Bridge (`/usr/local/bin/a2a-mcp-bridge`)**:
   - `lead-engineer`'s `Workspace.spec.mcp` registers `/usr/local/bin/a2a-mcp-bridge` ([`cmd/a2a-mcp-bridge/main.go`](./cmd/a2a-mcp-bridge/main.go)), which exposes the `delegate_to_actor(actor, prompt, context_id)` MCP tool.
   - `lead-engineer`'s Substrate `EgressPolicy` permits `TlsPassthrough` on port `443` to both `*.googleapis.com` and `atenet-router.ate-system.svc.cluster.local` / `atenet-router.ate-system.svc`.
2. **Wake-on-Request from Inside a gVisor Sandbox (`10.77s` specialist wake + audit)**:
   - `security-specialist` starts in the `Suspended` phase (`WORKER-IP: <none>`).
   - Sending **one** A2A gRPC `SendStreamingMessage` request to `lead-engineer` causes its Genkit tool loop to call `a2abridge_delegate_to_actor(actor="security-specialist", ...)`, which dials `atenet-router.ate-system.svc.cluster.local:443` over mTLS directly from inside `lead-engineer`'s gVisor sandbox, wakes `security-specialist` on a second gVisor worker, receives the security audit over A2A gRPC, patches `/workspace/webhook_handler.go`, and logs telemetry to `/workspace/.genkit/mcp-delegation.jsonl`.
