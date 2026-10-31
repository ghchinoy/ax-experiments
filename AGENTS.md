# AX Experiments — Agent Contract

Companion repository for multi-agent swarm experiments, trace visualization, and
local macOS Apple `container` (`ate-local`) proposals against
[`google/ax`](https://github.com/google/ax) and
[`go.ate.dev/substrate`](https://github.com/agent-substrate/substrate).

`CLAUDE.md` and `GEMINI.md` are symlinks to this file.

## Issue Tracking

This project uses **bd (beads)** for issue tracking.
Run `bd prime` for workflow context, or install hooks (`bd hooks install`) for auto-injection.

**Quick reference:**
- `bd ready` - Find unblocked work
- `bd create "Title" --type task --priority 2` - Create issue
- `bd close <id>` - Complete work
- `bd dolt push` - Push beads to remote

For full workflow details: `bd prime`

## Layout

```
genkit/                 Genkit Go runner (google/ax#538) manifests & GCE E2E bootstrap
swarm/                  Runnable multi-agent swarm & sandbox recipes (01–08)
  agent-image/          arm64 Gemini agent image (reads Task.spec.config via loopback metadata)
  lib.sh                Shared orchestration & opt-in trace emission helpers
viz/                    Swarm trace recorder & interactive web visualizer
  SCHEMA.md             JSONL trace event schema
  recorder/             Go trace recorder (ax-trace)
  traces/               Recorded swarm execution traces (.jsonl)
  web/                  Lit 3 + Force-Graph + Cytoscape CoSE replay app
docs/                   Architecture proposals, testing guides, and telemetry RFCs
```

## Registering & Running Experiments with `bd`

Every experiment MUST be registered in `bd` before execution and linked to the
`~/projects/ax` branch (upstream or fork) it exercises:

1. **Create the experiment bead**:
   - **Epics (`--type=epic`)**: Research tracks or fork branches.
   - **Experiments (`--type=spike` or `--type=feature`, `--parent=<epic-id>`)**: Individual runnable experiments (`swarm/01..08`) or prototype branches.
   - **Decisions (`--type=decision`)**: Architectural outcomes and upstream alignment choices.
   - **Required association flags**:
     - `--labels`: `repo:fork|upstream|substrate`, `branch:<name>`, `upstream:<issue-or-pr>`, `area:swarm|atelocal|viz|telemetry`
     - `--external-ref`: Primary upstream issue/PR or fork branch (e.g., `google/ax#526` or `ghchinoy/ax:feat/ate-local-apple-container`)
     - `--spec-id`: Relative path to the proposal/RFC in `docs/`
     - `--assignee`: Target experiment agent (`agent-substrate`, `agent-swarm`, `agent-viz`, `agent-sync`)
     - `--metadata`: JSON pin with `ax_repo`, `target_remote`, `target_branch`, `upstream_base`, `entrypoint`, and optional `trace`

   Example:
   ```bash
   bd create "Experiment title" \
     --type=spike \
     --parent=<epic-id> \
     --assignee=agent-swarm \
     --external-ref="ghchinoy/ax:feat/ate-local-apple-container" \
     --spec-id="docs/PROPOSAL-apple-container-substrate.md" \
     --labels="repo:fork,branch:feat/ate-local-apple-container,area:swarm" \
     --metadata='{"ax_repo":"/Users/ghchinoy/projects/ax","target_remote":"origin","target_branch":"feat/ate-local-apple-container","upstream_base":"f0228f1","entrypoint":"swarm/08-spec-config-metadata.sh"}' \
     --description="Hypothesis and what this experiment tests" \
     --acceptance="Pass/fail criteria and expected telemetry"
   ```

2. **Run against an isolated AX stack**:
   Always use isolated ports and `AX_LOCAL_DIR` in `/private/var/folders/qs/4zfn7mrs7kq23y6rgjnd_zxc0000gn/T/opencode/`
   when testing against `~/projects/ax` so you never disturb a running stack:
   ```bash
   AX_LOCAL_DIR=/private/var/folders/qs/4zfn7mrs7kq23y6rgjnd_zxc0000gn/T/opencode/ax-exp \
   AX_LOCAL_POSTGRES_PORT=5441 \
   AX_LOCAL_SUBSTRATE_PORT=50061 \
   AX_LOCAL_SERVER_PORT=8096 \
   AX_LOCAL_POSTGRES_NAME=ax-exp-postgres \
   ~/projects/ax/examples/ate_local/local-stack.sh up
   ```

3. **Record results & lineage**:
   - Store measured timings and observations with `bd update <id> --notes="..."`.
   - When an upstream change supersedes an experiment, link the new bead with
     `bd supersede <old-id> --with=<new-id>`.

## Verification Gates

- **Swarm scripts**: `bash -n swarm/*.sh` and run non-LLM recipes (`01`, `07`, `08`) against an isolated stack.
- **Trace recorder**: `cd viz/recorder && go build ./... && go vet ./...`
- **Web visualizer**: `cd viz/web && pnpm typecheck && pnpm build`
