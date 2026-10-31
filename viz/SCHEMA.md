# AX Swarm Execution Trace Schema (`trace.jsonl`)

The AX Swarm Execution Trace is a stream of timestamp-ordered JSON Lines (`.jsonl`) events capturing both **infrastructure lifecycle** (from AX and Substrate) and **collaborative swarm communication** (between the host and microVM sandboxes).

---

## Event Format

Each line is a single self-contained JSON object:

```json
{
  "t": 1790441234.512,
  "src": "ax|controller|recipe",
  "kind": "node.add|node.phase|node.ready|node.remove|edge.msg|edge.exec|ctl.step|note|run.start|run.end",
  "id": "debate-critic",
  "from": "host",
  "to": "debate-critic",
  "phase": "Running",
  "workerIP": "192.168.64.58",
  "role": "agent|worker|host|control",
  "label": "Prompt payload (412 chars)",
  "meta": {
    "exitCode": 0,
    "duration": 1.23,
    "seed": 101
  }
}
```

---

## Fields Definition

| Field | Type | Description |
|---|---|---|
| `t` | `float64` | **Required.** Unix epoch timestamp in seconds with millisecond resolution (`time.time()`). |
| `src` | `string` | **Required.** Event producer: `"ax"` (Valkey pub/sub), `"controller"` (parsed slog), or `"recipe"` (script orchestrator). |
| `kind` | `string` | **Required.** The event classification (see Event Kinds below). |
| `id` | `string` | Node or entity identifier (e.g. task name, or `"host"`, `"control-plane"`). |
| `from` | `string` | Source node ID for directional interactions or edges. |
| `to` | `string` | Target node ID for directional interactions or edges. |
| `phase` | `string` | Task lifecycle phase: `"Pending"`, `"Suspended"`, `"Running"`, `"Terminating"`, `"Completed"`, `"Failed"`. |
| `workerIP` | `string` | Dynamically assigned IPv4 on the macOS `vmnet` bridge (`192.168.64.x`). |
| `role` | `string` | High-level architectural role: `"agent"`, `"worker"`, `"host"`, `"control"`, or specialized role name. |
| `label` | `string` | Short human-readable display label. |
| `meta` | `object` | Optional key-value dictionary for metrics, payload previews, exit codes, and durations. |

---

## Event Kinds

| Event Kind | Source | Description | Graph Visualization Impact |
|---|---|---|---|
| `run.start` | `recipe` | Marks the start of a swarm scenario execution. | Resets timeline clock; renders title card. |
| `run.end` | `recipe` | Marks the completion and teardown of the swarm. | Finalizes total elapsed time and peak stats. |
| `node.add` | `recipe`/`ax` | Task manifest applied to AX (`ax apply`). | Spawns a new node connected to `host`. |
| `node.phase` | `ax` | Task phase changed in Valkey pub/sub. | Updates node color (e.g. yellow for Suspended, green for Running). |
| `node.ready` | `ax` | Container has passed HTTP `/readyz` probe on port 80. | Activates node pulse; reveals `workerIP` badge. |
| `node.remove` | `ax` | Task has been deleted and container removed. | Fades out and removes node from physics simulation. |
| `ctl.step` | `controller` | Controller lifecycle step (template ensure, actor resume/suspend). | Triggers activity indicator on `control-plane` node. |
| `edge.exec` | `recipe` | `ax ssh` execution started or ended inside container. | Renders interactive edge with execution progress. |
| `edge.msg` | `recipe` | Host relays message/data payload between agents. | Emits directional animated particles across edge. |
| `note` | `recipe` | Human milestone marker (e.g. "Round 2: Rebuttal"). | Appends callout badge in event log pane. |
