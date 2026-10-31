---
type: Agent Contract
title: "AX Experiments — Agent Contract"
description: "Agent workflow contract, per-folder OKF v0.2 metadata ruleset, optional fork/branch/upstream lineage schema, and Beads (bd) experiment tracking guidelines."
status: stable
tags: [contract, okf, beads, workflow, governance]
generated:
  by: human:ghchinoy
  at: 2026-10-31T00:00:00Z
verified:
  - by: human:ghchinoy
    at: 2026-10-31T00:00:00Z
---

# AX Experiments — Agent Contract

Companion repository for multi-agent swarm experiments, declarative runner prototypes,
trace visualization, and local macOS Apple `container` (`ate-local`) proposals against
[`google/ax`](https://github.com/google/ax) and
[`go.ate.dev/substrate`](https://github.com/agent-substrate/substrate).

`CLAUDE.md` and `GEMINI.md` are symlinks to this file.

## Per-Folder Experiment Layout (No Shared `./docs/`)

Every experiment track lives in its own self-contained top-level directory containing its
`README.md`, runnable scripts/manifests, and deep-dive design docs, tutorials, or RFCs.
Do **not** create a generic `./docs/` directory.

```
index.md                OKF v0.2 root bundle index (the ONLY index.md carrying frontmatter)
README.md               Repository overview, 4-track index, quickstart & verification gates
ate-local/              Track 1: Native macOS Apple container Substrate (google/ax#526)
  README.md             Track overview & quick verification commands
  PROPOSAL.md           Architecture proposal, concept mapping & Apple Silicon benchmarks
  TESTING.md            Automated unit/live microVM test suite & local stack walkthrough
  archive/              Archived early proposal and glidepath drafts
swarm/                  Track 2a: Runnable multi-agent swarm & sandbox recipes (01–08)
  README.md             Recipe catalog (01–08) & quickstart
  GUIDE.md              Developer guide, 3 swarm patterns & empirical timings
  agent-image/          arm64 Gemini agent image (reads Task.spec.config via loopback metadata)
  lib.sh                Shared orchestration & opt-in trace emission helpers
genkit/                 Track 2b: Declarative Genkit Go runner (google/ax#538)
  README.md             Track overview, manifest catalog & Apple container quickstart
  TUTORIAL.md           3-part tutorial (local Linux, GCE Kind + Substrate v0.6.0, Apple container)
  workspace.yaml        Workspace with inline files, incident-runbook SKILL.md & stdio MCP server
  task.yaml             Vertex AI / Linux & GCE Task manifest
  task-apple-container.yaml  Apple container microVM Task manifest
  run-apple-container.sh     E2E Apple container runner (A2A + MCP + Suspend/Resume)
  bootstrap-gce.sh      Ubuntu 24.04 GCE startup script (Kind + Substrate v0.6.0 + AX + Genkit)
viz/                    Track 3: Swarm trace recorder, web visualizer & telemetry RFC
  README.md             Visualizer & recorder quickstart
  SCHEMA.md             JSONL trace event schema
  FRICTION-REPORT.md    Correlation IDs, swarm lineage & W3C TraceContext RFC
  recorder/             Go trace recorder (ax-trace)
  traces/               Recorded swarm execution traces (.jsonl)
  web/                  Lit 3 + Force-Graph + Cytoscape CoSE replay app
```

## OKF v0.2 Knowledge Bundle & Optional Lineage Ruleset

This repository is a conformant **Open Knowledge Format (OKF) v0.2** bundle (`okf_version: "0.2"`):

1. **Root `index.md`**: Declares `okf_version: "0.2"` in YAML frontmatter (the **only** `index.md` allowed to carry frontmatter per OKF §8/§12) and indexes every track and concept document using bundle-relative `/path` links.
2. **Every non-reserved `.md` file is an OKF concept**: Must begin with YAML frontmatter containing a non-empty `type` (`Experiment Track`, `Architecture Proposal`, `Verification Guide`, `Developer Guide`, `Experiment Tutorial`, `Telemetry RFC`, `Schema Specification`, etc.), `title`, `description`, `status` (`draft` | `stable` | `deprecated`), and `generated: { by: ..., at: ... }`. Never store a computed trust tier or credibility score (§5.3).
3. **Optional `0..N` Upstream & Fork Lineage (`sources` + `experiment`)**:
   An experiment **may or may not** be associated with a fork, one or more branches in a fork, or upstream `google/ax` / `substrate` Issues and PRs. Record whatever lineage actually applies (all subfields in `experiment:` are optional):
   ```yaml
   sources:
     - id: ax-issue-538
       resource: https://github.com/google/ax/issues/538
       title: "google/ax#538: Genkit Go runner"
   experiment:
     track: genkit
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

This project uses **bd (beads)** for issue tracking (`bd ready`, `bd list --all`, `bd show <id>`; see [`/.beads/README.md`](/.beads/README.md)).

1. **Create the experiment bead**:
   - **Epics (`--type=epic`)**: Research tracks (`ate-local`, `swarm`, `genkit`, `viz`).
   - **Experiments (`--type=spike` or `--type=feature`, `--parent=<epic-id>`)**: Individual runnable experiments or prototype branches.
   - **Decisions (`--type=decision`)**: Architectural outcomes and upstream alignment choices.
   - **Association flags (include fork/branch/upstream fields when applicable)**:
     - `--labels`: `repo:companion|fork|upstream|substrate`, `area:atelocal|swarm|genkit|viz|telemetry`, plus optional `branch:<name>` and `upstream:<issue-or-pr>`
     - `--external-ref`: *(Optional)* Primary upstream issue/PR or fork branch (e.g., `google/ax#538` or `ghchinoy/ax:feat/ate-local-apple-container`)
     - `--spec-id`: Per-folder relative path to the experiment's doc/spec (e.g., `ate-local/PROPOSAL.md`, `genkit/TUTORIAL.md`, `swarm/GUIDE.md`, `viz/FRICTION-REPORT.md`)
     - `--assignee`: Target experiment agent (`agent-substrate`, `agent-swarm`, `agent-viz`, `agent-sync`)
     - `--metadata`: JSON pin with `entrypoint` and optional `ax_repo`, `target_remote`, `target_branch` (or `target_branches`), `upstream_base`, `trace`

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

- **OKF v0.2 bundle conformance**: `~/projects/binder/bin/binder validate . --strict` and `~/projects/binder/bin/binder review .`
- **Swarm & Genkit scripts**: `bash -n swarm/*.sh genkit/*.sh` and run non-LLM recipes (`01`, `07`, `08`) against an isolated stack.
- **Trace recorder**: `cd viz/recorder && go build ./... && go vet ./...`
- **Web visualizer**: `cd viz/web && pnpm typecheck && pnpm build`
