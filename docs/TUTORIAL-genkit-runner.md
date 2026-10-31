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
