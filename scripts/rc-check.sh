#!/usr/bin/env bash
# Copyright 2026 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Tiered Release-Candidate (RC) validation & regression scorecard runner across
# ax-experiments, ~/projects/ax, ~/projects/ax-images, and ~/projects/ax-central.
#
# Usage:
#   scripts/rc-check.sh [--tier static|quick|full|bench] [--rc <version>] [--out <dir>] [--all-swarms]
#
# Tiers:
#   static  Offline unit tests, OKF v0.2 strict validation, linters, Go builds/vets (~30s)
#   quick   static + live zero-LLM checks on :8090 (ate-local, ax-central smoke, swarm 01/02/03/07/08,
#           and live GHCR genkit-runner #688 AwaitPush A2A card check) (~60s)
#   full    quick + LLM/Hero-Demo/Genkit/dgem/agy checks (auto-skips missing optional deps) (~3-6m)
#   bench   quick + ate-local/bench/ax-local-timing.sh Kind comparison (~15m)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXP_REPO="$(cd "${SCRIPT_DIR}/.." && pwd)"
AX_REPO="${AX_REPO:-$HOME/projects/ax}"
AX_IMAGES_REPO="${AX_IMAGES_REPO:-$HOME/projects/ax-images}"
AX_CENTRAL_REPO="${AX_CENTRAL_REPO:-$HOME/projects/ax-central}"

TIER="quick"
RC_VERSION="${RC_VERSION:-}"
OUT_DIR="${OUT_DIR:-${EXP_REPO}/reports}"
ALL_SWARMS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tier) TIER="$2"; shift 2 ;;
    --rc) RC_VERSION="$2"; shift 2 ;;
    --out) OUT_DIR="$2"; shift 2 ;;
    --all-swarms) ALL_SWARMS=1; shift ;;
    -h|--help)
      sed -n '16,30p' "$0"
      exit 0
      ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

case "${TIER}" in
  static|quick|full|bench) ;;
  *) echo "Invalid --tier '${TIER}' (expected: static, quick, full, bench)" >&2; exit 2 ;;
esac

if [[ -z "${RC_VERSION}" ]]; then
  RC_VERSION="$(git -C "${AX_REPO}" describe --tags --abbrev=0 upstream/main 2>/dev/null || echo "dev")"
fi

STAMP_DATE="$(date -u +%Y-%m-%d)"
STAMP_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
SAFE_RC="$(printf '%s' "${RC_VERSION}" | tr '/ ' '__')"
LOG_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ax-rc-check-XXXXXX")"
RESULTS_JSONL="${LOG_DIR}/results.jsonl"
: > "${RESULTS_JSONL}"

mkdir -p "${OUT_DIR}"
MD_REPORT="${OUT_DIR}/${SAFE_RC}.md"
JSON_REPORT="${OUT_DIR}/${SAFE_RC}.json"

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
T_SUITE_START="$(python3 -c 'import time; print(time.time())')"

record_result() {
  local tier="$1" track="$2" id="$3" title="$4" status="$5" secs="$6" note="$7" log_file="${8:-}"
  case "${status}" in
    PASS) PASS_COUNT=$((PASS_COUNT + 1)); icon="🟢 PASS" ;;
    FAIL) FAIL_COUNT=$((FAIL_COUNT + 1)); icon="🔴 FAIL" ;;
    SKIP) SKIP_COUNT=$((SKIP_COUNT + 1)); icon="🟡 SKIP" ;;
  esac
  printf '  %-8s [%-24s] %5ss  %s — %s\n' "${icon}" "${id}" "${secs}" "${title}" "${note}"
  python3 - "${RESULTS_JSONL}" "${tier}" "${track}" "${id}" "${title}" "${status}" "${secs}" "${note}" "${log_file}" <<'PY'
import json, sys
out, tier, track, cid, title, status, secs, note, logfile = sys.argv[1:10]
tail = ""
if status == "FAIL" and logfile:
    try:
        lines = open(logfile, errors="replace").read().splitlines()
        tail = "\n".join(lines[-15:])
    except OSError:
        pass
rec = {
    "tier": tier, "track": track, "id": cid, "title": title,
    "status": status, "seconds": float(secs), "note": note, "tail": tail,
}
with open(out, "a") as f:
    f.write(json.dumps(rec) + "\n")
PY
}

run_check() {
  local tier="$1" track="$2" id="$3" title="$4" note_ok="$5"
  shift 5
  local log_file="${LOG_DIR}/${id}.log"
  local t0 t1 secs rc
  t0="$(python3 -c 'import time; print(time.time())')"
  if "$@" > "${log_file}" 2>&1; then
    rc=0
  else
    rc=$?
  fi
  t1="$(python3 -c 'import time; print(time.time())')"
  secs="$(python3 -c "print(f'{${t1} - ${t0}:.1f}')")"
  if [[ "${rc}" == "0" ]]; then
    record_result "${tier}" "${track}" "${id}" "${title}" "PASS" "${secs}" "${note_ok}" "${log_file}"
  else
    local first_err
    first_err="$(grep -iE "error:|fail|fatal|assertion|invalid" "${log_file}" | tail -n 1 | cut -c1-120 || true)"
    [[ -z "${first_err}" ]] && first_err="exit ${rc} (see ${log_file})"
    record_result "${tier}" "${track}" "${id}" "${title}" "FAIL" "${secs}" "${first_err}" "${log_file}"
  fi
}

skip_check() {
  local tier="$1" track="$2" id="$3" title="$4" reason="$5"
  record_result "${tier}" "${track}" "${id}" "${title}" "SKIP" "0.0" "${reason}" ""
}

genkit_ghcr_live_smoke() {
  local ax_bin="${AX_REPO}/.ax-local/bin/ax"
  local img
  img="$(grep -m1 'ghcr.io/ghchinoy/ax-images/genkit-runner@sha256:' "${EXP_REPO}/genkit/task.yaml" | sed 's/.*"\(.*\)".*/\1/')"
  if [[ -z "${img}" ]]; then
    echo "error: could not extract pinned genkit-runner image from genkit/task.yaml" >&2
    return 1
  fi
  export AX_SERVER="${AX_SERVER:-localhost:8090}"
  export ATENET_ROUTER_ADDR="${ATENET_ROUTER_ADDR:-127.0.0.1:50051}"
  local tname="rc-genkit-smoke-$$"
  trap "'${ax_bin}' delete task '${tname}' >/dev/null 2>&1 || true; trap - RETURN" RETURN
  cat <<EOF | "${ax_bin}" apply -f -
apiVersion: ax.io/v1alpha1
kind: Task
metadata:
  name: "${tname}"
spec:
  profile:
    image: "${img}"
  debug: true
  config:
    name: rc_smoke
    description: RC validation push-mode genkit-runner smoke.
    model: googleai/gemini-3.8-flash
    instruction: Smoke test agent.
  env:
    - name: GEMINI_API_KEY
      value: "placeholder-smoke-only"
EOF
  "${ax_bin}" resume "${tname}"
  local state
  state="$("${ax_bin}" describe task "${tname}" | awk '/^State:/{print $2; exit}')"
  if [[ "${state}" != "Running" && "${state}" != "Working" ]]; then
    echo "error: expected Running, got '${state}'" >&2
    return 1
  fi
  "${ax_bin}" ssh "${tname}" -- test -x /usr/local/bin/ax-runner -a -x /usr/local/bin/ax-launcher
  local card
  card="$(curl -fsS -H "ate-target-actor: default/${tname}" "http://${ATENET_ROUTER_ADDR}/.well-known/agent-card.json")"
  echo "${card}" | grep -q '"name":"rc_smoke"' || { echo "error: unexpected agent card: ${card}" >&2; return 1; }
  "${ax_bin}" delete task "${tname}"
}

echo "=================================================================="
echo "  AX Release-Candidate Validation · RC=${RC_VERSION} · Tier=${TIER}"
echo "  Logs: ${LOG_DIR}"
echo "=================================================================="

# --- Tier 0: Static & Unit ---
echo ""
echo "==> Tier 0: Static & Unit Gates"
run_check "T0" "ax-experiments" "exp-make-check" "OKF v0.2 + bash -n + 4 Go builds/vets" \
  "OKF strict 100%, shell syntax & Go builds green" \
  make -C "${EXP_REPO}" check

if [[ -d "${AX_IMAGES_REPO}" ]]; then
  run_check "T0" "ax-images" "images-go-test" "go vet & go test -race ./..." \
    "All image runner & launcher unit tests green" \
    bash -c "cd '${AX_IMAGES_REPO}' && go vet ./... && go test -race -count=1 ./..."
else
  skip_check "T0" "ax-images" "images-go-test" "go vet & go test -race ./..." "${AX_IMAGES_REPO} not found"
fi

if [[ -d "${AX_CENTRAL_REPO}" ]]; then
  run_check "T0" "ax-central" "central-make-check" "make check (Go -race, lint, audit, Vitest+axe)" \
    "Lint, 0 audit vulns, Go -race & Vitest green" \
    make -C "${AX_CENTRAL_REPO}" check
else
  skip_check "T0" "ax-central" "central-make-check" "make check" "${AX_CENTRAL_REPO} not found"
fi

if [[ -d "${AX_REPO}/internal/atelocal" ]]; then
  run_check "T0" "ax-fork" "atelocal-unit" "go test ./internal/atelocal (unit suite)" \
    "ControlServer, Podman, Tag/Router & PreBoot unit tests green" \
    bash -c "cd '${AX_REPO}' && go test -count=1 -run 'TestControlServer_(Atespace|Actor|Revert|Template|Reconciler)|TestCleanIPv4|TestPodmanRunner|TestTagAndRouterProxy|TestPreBoot' ./internal/atelocal/..."
else
  skip_check "T0" "ax-fork" "atelocal-unit" "ate-local unit tests" "${AX_REPO}/internal/atelocal not found"
fi

# --- Tier 1: Quick Live Smoke ---
if [[ "${TIER}" != "static" ]]; then
  echo ""
  echo "==> Tier 1: Quick Live RC Smoke (zero-LLM, :8090 ate-local)"
  STACK_UP=0
  if nc -z 127.0.0.1 8090 >/dev/null 2>&1 && nc -z 127.0.0.1 50051 >/dev/null 2>&1; then
    STACK_UP=1
  fi

  if [[ "${STACK_UP}" != "1" ]]; then
    skip_check "T1" "stack" "live-tier1" "All Tier 1 live checks" "Local stack (:8090 / :50051) not listening; run 'make stack-up'"
  else
    run_check "T1" "ax-fork" "atelocal-live" "Live Apple container + reconciler guest-exec" \
      "Live microVM ControlServer & ax ssh green" \
      bash -c "cd '${AX_REPO}' && go test -count=1 -run 'TestControlServer_LiveAppleContainer|TestControlServer_LiveReconcilerAndGuestExec' ./internal/atelocal/..."

    if [[ -d "${AX_CENTRAL_REPO}" ]]; then
      run_check "T1" "ax-central" "central-doctor" "make doctor (6-point prerequisite audit)" \
        "All prerequisites verified" \
        make -C "${AX_CENTRAL_REPO}" doctor
      run_check "T1" "ax-central" "central-smoke-local" "make smoke-local (debian:12 + Move Task tar)" \
        "Apply/resume, ax ssh & cross-atespace tar pipe green" \
        make -C "${AX_CENTRAL_REPO}" smoke-local
    fi

    run_check "T1" "swarm" "swarm-01" "01-hello-swarm (8 parallel microVMs)" \
      "8 parallel Apple container microVMs Ready & ax ssh ok" \
      bash "${EXP_REPO}/swarm/01-hello-swarm.sh"
    run_check "T1" "swarm" "swarm-02" "02-repo-inspector (Workspace git + inline)" \
      "Workspace git clone & inline files hydrated across 3 VMs" \
      bash "${EXP_REPO}/swarm/02-repo-inspector.sh"
    run_check "T1" "swarm" "swarm-03" "03-seed-matrix (6 parallel sweep VMs)" \
      "6 parallel matrix tasks completed" \
      bash "${EXP_REPO}/swarm/03-seed-matrix.sh"
    run_check "T1" "swarm" "swarm-07" "07-suspend-resume (#683 cold-start persistence)" \
      "Volume state persisted across suspend -> fresh VM boot" \
      bash "${EXP_REPO}/swarm/07-suspend-resume.sh"
    run_check "T1" "swarm" "swarm-08" "08-spec-config-metadata (:8099 boundary)" \
      "External :80/metadata 404; loopback :8099 metadata & config ok" \
      bash "${EXP_REPO}/swarm/08-spec-config-metadata.sh"
    run_check "T1" "ax-images" "images-genkit-live" "GHCR genkit-runner #688 AwaitPush + A2A card" \
      "Pulled @sha256, verified ax-runner/ax-launcher & A2A card via router" \
      genkit_ghcr_live_smoke
  fi
fi

# --- Tier 2: Full In-Depth Sweep ---
if [[ "${TIER}" == "full" ]]; then
  echo ""
  echo "==> Tier 2: Full In-Depth RC Sweep (LLM, Hero Demo, Genkit, dgem, agy)"
  if [[ "${STACK_UP:-0}" != "1" ]]; then
    skip_check "T2" "stack" "live-tier2" "All Tier 2 live checks" "Local stack (:8090) not listening"
  elif [[ -z "${GEMINI_API_KEY:-}" ]]; then
    skip_check "T2" "hero-demo" "hero-demo-live" "5/5 Live Hero Demo" "GEMINI_API_KEY unset"
    skip_check "T2" "genkit" "genkit-apple" "genkit/run-apple-container.sh" "GEMINI_API_KEY unset"
    skip_check "T2" "swarm" "swarm-04-review" "04-review-panel" "GEMINI_API_KEY unset"
    skip_check "T2" "agy" "agy-01-baseline" "agy/01-phase1-baseline.sh" "GEMINI_API_KEY unset"
    skip_check "T2" "dgem" "dgem-suite" "dgem/01..03" "GEMINI_API_KEY unset"
  else
    run_check "T2" "hero-demo" "hero-demo-live" "5/5 Live Hero Demo (hero-demo/run-live.sh)" \
      "Hero Demo completed" \
      bash "${EXP_REPO}/hero-demo/run-live.sh"
    run_check "T2" "genkit" "genkit-apple" "genkit/run-apple-container.sh (A2A + MCP + suspend)" \
      "Genkit Apple container E2E passed" \
      bash "${EXP_REPO}/genkit/run-apple-container.sh"
    run_check "T2" "swarm" "swarm-04-review" "04-review-panel (3 Gemini reviewers)" \
      "3-reviewer Gemini swarm passed" \
      bash "${EXP_REPO}/swarm/04-review-panel.sh"
    if [[ "${ALL_SWARMS}" == "1" ]]; then
      run_check "T2" "swarm" "swarm-05-debate" "05-debate" "Adversarial debate swarm passed" bash "${EXP_REPO}/swarm/05-debate.sh"
      run_check "T2" "swarm" "swarm-06-mapreduce" "06-map-reduce" "Map-reduce swarm passed" bash "${EXP_REPO}/swarm/06-map-reduce.sh"
    fi
    run_check "T2" "agy" "agy-01-baseline" "agy/01-phase1-baseline.sh (ax-image)" \
      "Antigravity Phase 1 baseline passed" \
      env SURFACE=ax-image bash "${EXP_REPO}/agy/01-phase1-baseline.sh"
    if nc -z 127.0.0.1 8095 >/dev/null 2>&1; then
      run_check "T2" "dgem" "dgem-01" "dgem/01-tool-approval-microvm.sh" "dgem ToolApproval passed" bash "${EXP_REPO}/dgem/01-tool-approval-microvm.sh"
      run_check "T2" "dgem" "dgem-02" "dgem/02-mcp-triage-agent.sh" "dgem MCP triage passed" bash "${EXP_REPO}/dgem/02-mcp-triage-agent.sh"
      run_check "T2" "dgem" "dgem-03" "dgem/03-specialist-router.sh" "dgem specialist router passed" bash "${EXP_REPO}/dgem/03-specialist-router.sh"
      run_check "T2" "agy" "agy-02-safety-gate" "agy/02-phase2-dgem-safety-gate.sh" "Antigravity Phase 2 dgem safety gate passed" bash "${EXP_REPO}/agy/02-phase2-dgem-safety-gate.sh"
    else
      skip_check "T2" "dgem" "dgem-suite" "dgem/01..03 + agy/02" "dgem gateway (:8095) not running; run 'make dgem-up'"
    fi
  fi
fi

# --- Tier 3: Kind Timing Benchmark ---
if [[ "${TIER}" == "bench" ]]; then
  echo ""
  echo "==> Tier 3: Kind Bring-Up Benchmark (ate-local/bench/ax-local-timing.sh)"
  BENCH_OUT="${LOG_DIR}/kind-bench"
  if podman info >/dev/null 2>&1 || docker info >/dev/null 2>&1; then
    run_check "T3" "ate-local" "kind-timing-bench" "ax local Kind timing benchmark" \
      "Completed Kind cold/resume/recreate timing" \
      env BENCH_DIR="${BENCH_OUT}" AX_VERSION="${RC_VERSION}" bash "${EXP_REPO}/ate-local/bench/ax-local-timing.sh"
  else
    skip_check "T3" "ate-local" "kind-timing-bench" "ax local Kind timing benchmark" \
      "Neither Docker nor a running Podman machine is available"
  fi
fi

T_SUITE_END="$(python3 -c 'import time; print(time.time())')"
TOTAL_SECS="$(python3 -c "print(f'{${T_SUITE_END} - ${T_SUITE_START}:.1f}')")"

# Gather provenance metadata across all 4 repos
UPSTREAM_SHA="$(git -C "${AX_REPO}" rev-parse --short upstream/main 2>/dev/null || echo "unknown")"
FORK_SHA="$(git -C "${AX_REPO}" rev-parse --short HEAD 2>/dev/null || echo "unknown")"
FORK_BRANCH="$(git -C "${AX_REPO}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")"
SUBSTRATE_VER="$(grep 'go.ate.dev/substrate ' "${AX_REPO}/go.mod" 2>/dev/null | awk '{print $2}' | head -n1 || echo "unknown")"
IMAGES_TAG="$(git -C "${AX_IMAGES_REPO}" describe --tags --abbrev=0 2>/dev/null || echo "unknown")"
IMAGES_SHA="$(git -C "${AX_IMAGES_REPO}" rev-parse --short HEAD 2>/dev/null || echo "unknown")"
CENTRAL_SHA="$(git -C "${AX_CENTRAL_REPO}" rev-parse --short HEAD 2>/dev/null || echo "unknown")"
EXP_SHA="$(git -C "${EXP_REPO}" rev-parse --short HEAD 2>/dev/null || echo "unknown")"
HOST_CPU="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || uname -m)"
HOST_OS="$(sw_vers -productVersion 2>/dev/null || uname -sr)"
CONTAINER_VER="$(container --version 2>/dev/null | head -n1 || echo "unavailable")"
GO_VER="$(go version 2>/dev/null | awk '{print $3}' || echo "unknown")"

# Emit JSON + Markdown scorecard
python3 - "${RESULTS_JSONL}" "${JSON_REPORT}" "${MD_REPORT}" \
  "${RC_VERSION}" "${TIER}" "${STAMP_DATE}" "${STAMP_ISO}" "${TOTAL_SECS}" \
  "${UPSTREAM_SHA}" "${SUBSTRATE_VER}" "${FORK_BRANCH}" "${FORK_SHA}" \
  "${IMAGES_TAG}" "${IMAGES_SHA}" "${CENTRAL_SHA}" "${EXP_SHA}" \
  "${HOST_CPU}" "${HOST_OS}" "${CONTAINER_VER}" "${GO_VER}" <<'PY'
import json, sys

(jsonl_path, json_out, md_out,
 rc_ver, tier, date_s, iso_s, total_s,
 up_sha, sub_ver, fork_br, fork_sha,
 img_tag, img_sha, central_sha, exp_sha,
 host_cpu, host_os, container_ver, go_ver) = sys.argv[1:21]

rows = [json.loads(line) for line in open(jsonl_path) if line.strip()]
passed = sum(1 for r in rows if r["status"] == "PASS")
failed = sum(1 for r in rows if r["status"] == "FAIL")
skipped = sum(1 for r in rows if r["status"] == "SKIP")

payload = {
    "rc_version": rc_ver,
    "tier": tier,
    "timestamp": iso_s,
    "total_seconds": float(total_s),
    "summary": {"passed": passed, "failed": failed, "skipped": skipped, "total": len(rows)},
    "versions": {
        "google_ax_upstream": up_sha,
        "substrate": sub_ver,
        "ax_fork": f"{fork_br}@{fork_sha}",
        "ax_images": f"{img_tag}@{img_sha}",
        "ax_central": central_sha,
        "ax_experiments": exp_sha,
    },
    "host": {
        "cpu": host_cpu,
        "os": host_os,
        "container_cli": container_ver,
        "go": go_ver,
    },
    "checks": rows,
}
with open(json_out, "w") as f:
    json.dump(payload, f, indent=2)
    f.write("\n")

icon = {"PASS": "🟢 PASS", "FAIL": "🔴 FAIL", "SKIP": "🟡 SKIP"}
verdict = "🟢 PASS" if failed == 0 else f"🔴 FAIL ({failed} failed)"

lines = [
    f"# RC Validation Scorecard: `google/ax` `{rc_ver}` (`{tier}`)",
    "",
    f"> **Date**: {date_s} (`{iso_s}`) · **Verdict**: {verdict} ({passed} passed, {failed} failed, {skipped} skipped in {total_s}s) · **Bundle Index**: [`../okf/index.md`](../okf/index.md)",
    "",
    "## Version & Environment Pin",
    "",
    "| Component | Pin |",
    "|---|---|",
    f"| **Upstream `google/ax`** | `{rc_ver}` (`upstream/main` @ `{up_sha}`) |",
    f"| **Agent Substrate** | `{sub_ver}` |",
    f"| **Fork `ghchinoy/ax`** | `{fork_br}` @ `{fork_sha}` |",
    f"| **`ghchinoy/ax-images`** | `{img_tag}` (`{img_sha}`) |",
    f"| **`ghchinoy/ax-central`** | `main` @ `{central_sha}` |",
    f"| **`ghchinoy/ax-experiments`** | `main` @ `{exp_sha}` |",
    f"| **Host** | {host_cpu}, macOS {host_os}, `{go_ver}`, `{container_ver}` |",
    "",
    "## Scoreboard",
    "",
    "| Tier | Track / Repo | Check | Status | Time | Notes |",
    "|---|---|---|---|---:|---|",
]
for r in rows:
    note = r["note"].replace("|", "\\|")
    lines.append(
        f"| {r['tier']} | `{r['track']}` | {r['title']} (`{r['id']}`) | {icon[r['status']]} | {r['seconds']:.1f}s | {note} |"
    )

failed_rows = [r for r in rows if r["status"] == "FAIL"]
if failed_rows:
    lines += ["", "## Failure Diagnostics", ""]
    for r in failed_rows:
        lines += [
            f"### `{r['id']}` — {r['title']}",
            "",
            "```text",
            r["tail"] or "(no output captured)",
            "```",
            "",
        ]

lines += [
    "",
    "## Recommendations & Follow-Ups",
    "",
    "### Internal Actions (Our Repos)",
    "- *(Review any failed checks above and track follow-ups via `bd`.)*",
    "",
    "### Upstream Suggestions (`google/ax` & `agent-substrate/substrate`)",
    "- *(Record reproducible upstream friction, bugs, or proposals observed during this RC run.)*",
    "",
]

with open(md_out, "w") as f:
    f.write("\n".join(lines))
PY

echo ""
echo "=================================================================="
echo "  Scorecard: ${PASS_COUNT} passed, ${FAIL_COUNT} failed, ${SKIP_COUNT} skipped (${TOTAL_SECS}s)"
echo "  Markdown:  ${MD_REPORT}"
echo "  JSON:      ${JSON_REPORT}"
echo "=================================================================="

[[ "${FAIL_COUNT}" == "0" ]]
