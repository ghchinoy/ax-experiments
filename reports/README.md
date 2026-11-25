# Release-Candidate Validation Scorecards (`reports/`)

> **Bundle Index**: [`../okf/index.md`](../okf/index.md) · **Harness**: [`../scripts/rc-check.sh`](../scripts/rc-check.sh)

Historical regression scorecards generated against upstream `google/ax` release candidates (`v0.4.0-rc.2`, `v0.4.0`, …) across `ax-experiments`, `~/projects/ax` (`ate-local`), `~/projects/ax-images`, and `~/projects/ax-central`.

## Running a Validation Pass

```bash
# Tier 0: Offline static & unit gates across all 4 repos (~30s)
make rc-static RC_VERSION=v0.4.0-rc.2

# Tier 1: Quick live zero-LLM RC smoke against :8090 ate-local (~60s)
make rc-quick RC_VERSION=v0.4.0-rc.2

# Tier 2: Full sweep (+ Hero Demo, Genkit, LLM swarm, dgem, agy) (~3-6m)
make rc-full RC_VERSION=v0.4.0-rc.2

# Tier 3: Quick + Kind bring-up timing benchmark (~15m)
make rc-bench RC_VERSION=v0.4.0-rc.2
```

Each run writes `<RC_VERSION>.md` (human-readable scorecard + recommendations) and `<RC_VERSION>.json` (machine-readable timings for cross-RC comparison) into this directory.
