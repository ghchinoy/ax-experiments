# AX Experiments — Agent Contract

Companion repository for multi-agent swarm experiments, declarative runner prototypes,
trace visualization, and local macOS Apple `container` (`ate-local`) proposals against
[`google/ax`](https://github.com/google/ax) and
[`go.ate.dev/substrate`](https://github.com/agent-substrate/substrate).

`CLAUDE.md` and `GEMINI.md` are symlinks to this file.

## Per-Folder & External Experiment Layout (No Shared `./docs/`)

In-tree experiment tracks live in their own self-contained top-level directories containing their
human-facing `README.md` (free of YAML frontmatter so GitHub renders it cleanly), runnable
scripts/manifests, and deep-dive design docs, tutorials, or RFCs. Standalone experimental
projects that live outside this repository (such as `~/projects/ax-central`) are tracked via
first-class concept cards in [`okf/`](./okf/index.md) (`type: External Experiment`,
`experiment.location: external`) and `bd` epics. Do **not** create a generic `./docs/` directory.

```
README.md               Repository overview, track index, quickstart & verification gates
AGENTS.md               Agent contract, OKF v0.2 ruleset & Beads (bd) tracking rules
okf/                    OKF v0.2 Knowledge Bundle (provenance, trust & upstream/fork/external lineage)
  index.md              OKF v0.2 bundle root index (the ONLY index.md carrying frontmatter)
  ate-local.md          Track 1 concept card (`type: Experiment Track`, in-tree)
  crostini.md           Track 1b concept card (`type: Experiment Track`, in-tree)
  swarm.md              Track 2a concept card (`type: Experiment Track`, in-tree)
  genkit.md             Track 2b concept card (`type: Experiment Track`, in-tree)
  dgem.md               Track 2c concept card (`type: Experiment Track`, in-tree)
  viz.md                Track 3 concept card (`type: Experiment Track`, in-tree)
  ax-central.md         Track 4 concept card (`type: External Experiment`, ~/projects/ax-central)
ate-local/              Track 1: Native macOS Apple container Substrate (google/ax#526)
  README.md             Track overview & quick verification commands
  PROPOSAL.md           Architecture proposal, concept mapping & Apple Silicon benchmarks
  TESTING.md            Automated unit/live microVM test suite & local stack walkthrough
  archive/              Archived early proposal and glidepath drafts
crostini/               Track 1b: Local Chromebook / Crostini Kind + Agent Substrate Stack
  README.md             Track overview & quickstart
  GUIDE.md              Debian 13 (trixie) audit, Docker/Kind setup, resource tuning & benchmarks
  setup-crostini.sh     Idempotent setup script for Crostini / Bagels KVM VM
swarm/                  Track 2a: Runnable multi-agent swarm & sandbox recipes (01–08)
  README.md             Recipe catalog (01–08) & quickstart
  GUIDE.md              Developer guide, 3 swarm patterns & empirical timings
  agent-image/          arm64 Gemini agent image (reads Task.spec.config via loopback metadata)
  lib.sh                Shared orchestration & opt-in trace emission helpers
genkit/                 Track 2b: Declarative Genkit Go runner (google/ax#538)
  README.md             Track overview, manifest catalog & multi-agent quickstarts
  CONCEPTS_BRIEF.md     EGM Concepts Brief & 7-lens Goldfish synthesis for multi-agent examples
  TUTORIAL.md           4-part tutorial (local Linux, GCE Kind + Substrate, Apple container, multi-agent EGM/MCP)
  01-egm-review-panel.sh     Example 01: 1 Elephant + 3 parallel Goldfish reviewers over A2A gRPC
  02-in-cluster-delegation.sh Example 02: Autonomous in-sandbox MCP -> A2A gRPC delegation via atenet-router
  cmd/                  egm-orchestrator & static a2a-mcp-bridge stdio MCP server
  internal/axclient/    Shared EgressPolicy, router mTLS & A2A gRPC client package
  workspace.yaml        Workspace with inline files, incident-runbook SKILL.md & stdio MCP server
  task.yaml             Vertex AI / Linux & GCE Task manifest
  task-apple-container.yaml  Apple container microVM Task manifest
  run-apple-container.sh     E2E Apple container runner (A2A + MCP + Suspend/Resume)
  bootstrap-gce.sh      Ubuntu 24.04 GCE startup script (Kind + Substrate v0.6.0 + AX + Genkit)
dgem/                   Track 2c: System-1 Decision Routing & Guardrails with dgem + Genkit
  README.md             Track overview, recipe catalog & quickstart
  GUIDE.md              Setup guide, EndpointConfig reference & empirical M5 report
  01-tool-approval-microvm.sh  Recipe 01: systemonex + ToolApproval interrupt guardrail in microVM
  02-mcp-triage-agent.sh       Recipe 02: Declarative genkit-runner + dgem Streamable HTTP MCP
  03-specialist-router.sh      Recipe 03: 1-to-3 Hesitation-gated scale-to-zero specialist router
  router/               Standalone Go router CLI (dgem-router)
  templates/            specialist_router.json.tmpl policy
  manifests/            Declarative Workspace & Task manifests for router + 3 specialists
viz/                    Track 3: Swarm trace recorder, web visualizer & telemetry RFC
  README.md             Visualizer & recorder quickstart
  SCHEMA.md             JSONL trace event schema
  FRICTION-REPORT.md    Correlation IDs, swarm lineage & W3C TraceContext RFC
  recorder/             Go trace recorder (ax-trace)
  traces/               Recorded swarm execution traces (.jsonl)
  web/                  Lit 3 + Force-Graph + Cytoscape CoSE replay app
```

## Agent Roles & Folder Ownership

| Assignee | Owned Folders | Scope & Responsibilities |
|---|---|---|
| `agent-substrate` | [`ate-local/`](./ate-local/README.md), [`crostini/`](./crostini/README.md), [`okf/ate-local.md`](./okf/ate-local.md), [`okf/crostini.md`](./okf/crostini.md) | `ateapipb.ControlServer`, Apple `container` microVMs, Crostini Kind + gVisor stack, `local-stack.sh`, `#526`, `#553` |
| `agent-swarm` | [`swarm/`](./swarm/README.md), [`genkit/`](./genkit/README.md), [`dgem/`](./dgem/README.md), [`okf/swarm.md`](./okf/swarm.md), [`okf/genkit.md`](./okf/genkit.md), [`okf/dgem.md`](./okf/dgem.md) | Multi-agent recipes (`01`–`08`), `ax-agent-local` image, `genkit-runner` (`#538`), `dgem` + Genkit System-1 routing (`dgem/01..03`) |
| `agent-viz` | [`viz/`](./viz/README.md), [`okf/viz.md`](./okf/viz.md), [`okf/ax-central.md`](./okf/ax-central.md) | `SCHEMA.md`, `ax-trace` recorder, Lit 3 / Force-Graph / Cytoscape UI, telemetry RFC, `~/projects/ax-central` |
| `agent-sync` | [`okf/index.md`](./okf/index.md), [`README.md`](./README.md), [`AGENTS.md`](./AGENTS.md), `.beads/` | Upstream `google/ax` & `substrate` rebase checks, OKF v0.2 bundle conformance, `bd` hygiene |

## OKF v0.2 Knowledge Bundle (`okf/`) & Optional Lineage Ruleset

The [`okf/`](./okf/index.md) directory is a conformant **Open Knowledge Format (OKF) v0.2** bundle (`okf_version: "0.2"`), validated with [`ghchinoy/binder`](https://github.com/ghchinoy/binder) and [`ghchinoy/okf-proto`](https://github.com/ghchinoy/okf-proto):

1. **Keep human `README.md` files frontmatter-free**: Human-facing markdown files outside `okf/` (`README.md`, `<track>/README.md`, `PROPOSAL.md`, `TUTORIAL.md`, `GUIDE.md`, `FRICTION-REPORT.md`) start directly with `# Title` (no YAML frontmatter) and include a one-line pointer to their corresponding concept card in `okf/<track>.md`.
2. **Bundle root [`okf/index.md`](./okf/index.md)**: Declares `okf_version: "0.2"` in YAML frontmatter (the **only** `index.md` allowed to carry frontmatter per OKF §8/§12) and indexes every concept document in `okf/` using bundle-relative `/<track>.md` links.
3. **Concept cards (`okf/*.md`)**: Every non-reserved `.md` file inside `okf/` must begin with YAML frontmatter containing a non-empty `type` (`Experiment Track` for in-tree tracks, `External Experiment` for out-of-tree projects like `~/projects/ax-central`), `title`, `description`, `status` (`draft` | `stable` | `deprecated`), `generated: { by: ..., at: ... }`, and `verified:` once confirmed. Never store a computed trust tier or credibility score (§5.3).
4. **Optional `0..N` Upstream, Fork & External Location Lineage (`sources` + `experiment`)**:
   An experiment **may or may not** live in this monorepo (`location: in-tree | external`), and **may or may not** be associated with a fork, one or more branches in a fork, or upstream `google/ax` / `substrate` Issues and PRs. Record whatever lineage actually applies in `okf/<track>.md` (all subfields in `experiment:` are optional):
   ```yaml
   sources:
     - id: ax-issue-538
       resource: https://github.com/google/ax/issues/538
       title: "google/ax#538: Genkit Go runner"
   experiment:
     track: genkit
     location: in-tree             # in-tree | external
     folder: genkit/               # For in-tree tracks (use local_path: ~/projects/<name> for external)
     beads: [ax-experiments-c0h.3, ax-experiments-c0h.4]
     entrypoints: [genkit/run-apple-container.sh]
     upstream:                     # Optional: omit if purely repo-local/companion
       repo: google/ax             # google/ax | agent-substrate/substrate
       base_commit: f0228f1
       issues: [538, 526]          # Optional (0..N)
       prs: []                     # Optional (0..N)
     forks:                        # Optional (0..N): omit if no fork/branch is used
       - repo: ghchinoy/ax
         branch: feat/genkit-runner
   ```

## Issue Tracking & Registering Experiments with `bd`

This project uses **bd (beads)** for issue tracking (`bd ready`, `bd list --all`, `bd show <id>`).

1. **Create the experiment bead**:
   - **Epics (`--type=epic`)**: Research tracks (`ate-local`, `swarm`, `genkit`, `viz`, or external projects like `ax-central`).
   - **Experiments (`--type=spike` or `--type=feature`, `--parent=<epic-id>`)**: Individual runnable experiments or prototype branches.
   - **Decisions (`--type=decision`)**: Architectural outcomes and upstream alignment choices.
   - **Association flags (include fork/branch/upstream fields when applicable)**:
     - `--labels`: `repo:companion|external|fork|upstream|substrate`, `area:atelocal|swarm|genkit|viz|telemetry`, plus optional `branch:<name>` and `upstream:<issue-or-pr>`
     - `--external-ref`: *(Optional)* Primary upstream issue/PR or fork branch (e.g., `google/ax#538` or `ghchinoy/ax:feat/ate-local-apple-container`)
     - `--spec-id`: Relative path to the experiment's doc/spec or OKF card (e.g., `ate-local/PROPOSAL.md`, `genkit/TUTORIAL.md`, `swarm/GUIDE.md`, `viz/FRICTION-REPORT.md`, `okf/ax-central.md`)
     - `--assignee`: Target experiment agent (`agent-substrate`, `agent-swarm`, `agent-viz`, `agent-sync`)
     - `--metadata`: JSON pin with `entrypoint` and optional `local_path` (for `repo:external` projects), `ax_repo`, `target_remote`, `target_branch` (or `target_branches`), `upstream_base`, `trace`

   Example:
   ```bash
   bd create "Experiment title" \
     --type=spike \
     --parent=<epic-id> \
     --assignee=agent-swarm \
     --external-ref="ghchinoy/ax:feat/ate-local-apple-container" \
     --spec-id="ate-local/PROPOSAL.md" \
     --labels="repo:fork,branch:feat/ate-local-apple-container,area:swarm" \
     --metadata='{"ax_repo":"/Users/ghchinoy/projects/ax","target_remote":"origin","target_branch":"feat/ate-local-apple-container","upstream_base":"f0228f1","entrypoint":"swarm/08-spec-config-metadata.sh"}' \
     --description="Hypothesis and what this experiment tests" \
     --acceptance="Pass/fail criteria and expected telemetry"
   ```

2. **Isolate both `~/projects/ax` worktrees and local stack ports**:
   - **Worktree isolation**: Never run `git checkout` or `git merge` directly in `~/projects/ax` if another session may be using it. Create a temporary worktree under `/private/var/folders/qs/4zfn7mrs7kq23y6rgjnd_zxc0000gn/T/opencode/ax-wt-<name>` and pass `AX_REPO=<worktree>`:
     ```bash
     git -C ~/projects/ax worktree add /private/var/folders/qs/4zfn7mrs7kq23y6rgjnd_zxc0000gn/T/opencode/ax-wt-exp feat/ate-local-apple-container
     ```
   - **Stack port & state isolation**: Always use isolated ports and `AX_LOCAL_DIR` in `/private/var/folders/qs/4zfn7mrs7kq23y6rgjnd_zxc0000gn/T/opencode/` so you never disturb a running stack:
     ```bash
     AX_LOCAL_DIR=/private/var/folders/qs/4zfn7mrs7kq23y6rgjnd_zxc0000gn/T/opencode/ax-exp \
     AX_LOCAL_POSTGRES_PORT=5441 \
     AX_LOCAL_SUBSTRATE_PORT=50061 \
     AX_LOCAL_SERVER_PORT=8096 \
     AX_LOCAL_POSTGRES_NAME=ax-exp-postgres \
     ~/projects/ax/examples/ate_local/local-stack.sh up
     ```

3. **Record results & lineage**:
   - Store measured timings and observations with `bd update <id> --notes="..."` and update the corresponding `okf/<track>.md` concept card if new beads, entrypoints, or upstream issues/PRs were added.
   - When an upstream change supersedes an experiment, link the new bead with
     `bd supersede <old-id> --with=<new-id>`.

## Verification Gates (`make check`)

Run `make check` before committing, which executes:
- **OKF v0.2 bundle conformance** ([`ghchinoy/binder`](https://github.com/ghchinoy/binder) & [`ghchinoy/okf-proto`](https://github.com/ghchinoy/okf-proto)):
  `binder validate okf --strict`, `binder review okf --strict --require-tier human-reviewed`, and `okf-proto export okf --format json`
- **Swarm & Genkit scripts**: `bash -n swarm/*.sh genkit/*.sh` and run non-LLM recipes (`01`, `07`, `08`) against an isolated stack.
- **Trace recorder**: `cd viz/recorder && go build ./... && go vet ./...`
- **Web visualizer**: `cd viz/web && pnpm typecheck && pnpm build`


<!-- headroom:rtk-instructions -->
# RTK (Rust Token Killer) - Token-Optimized Commands

When running shell commands, **always prefix with `rtk`**. This reduces context
usage by 60-90% with zero behavior change. If rtk has no filter for a command,
it passes through unchanged — so it is always safe to use.

## Key Commands
```bash
# Git (59-80% savings)
rtk git status          rtk git diff            rtk git log

# Files & Search (60-75% savings)
rtk ls <path>           rtk read <file>         rtk grep <pattern>
rtk find <pattern>      rtk diff <file>

# Test (90-99% savings) — shows failures only
rtk pytest tests/       rtk cargo test          rtk test <cmd>

# Build & Lint (80-90% savings) — shows errors only
rtk tsc                 rtk lint                rtk cargo build
rtk prettier --check    rtk mypy                rtk ruff check

# Analysis (70-90% savings)
rtk err <cmd>           rtk log <file>          rtk json <file>
rtk summary <cmd>       rtk deps                rtk env

# GitHub (26-87% savings)
rtk gh pr view <n>      rtk gh run list         rtk gh issue list

# Infrastructure (85% savings)
rtk docker ps           rtk kubectl get         rtk docker logs <c>

# Package managers (70-90% savings)
rtk pip list            rtk pnpm install        rtk npm run <script>
```

## Rules
- In command chains, prefix each segment: `rtk git add . && rtk git commit -m "msg"`
- For debugging, use raw command without rtk prefix
- `rtk proxy <cmd>` runs command without filtering but tracks usage
<!-- /headroom:rtk-instructions -->
