#!/usr/bin/env bash
# Times each phase of `ax local` (Kind backend) for google/ax#689 and
# ate-local/LOCAL-BACKEND.md: cold start, stop, resume, delete, and recreate.
#
# Every output line is timestamped, and a monitor samples pod states every 10s
# because `ax local start` only prints a rollout wait when a container reports
# a waiting reason.
#
# Isolated from any existing setup: own KUBECONFIG, AX_HOME, and cluster name.
#
# Environment:
#   BENCH_DIR             Output and state directory (required)
#   AX_BIN                ax CLI with `ax local` (default: download AX_VERSION)
#   AX_VERSION            Release to download when AX_BIN is unset (default v0.4.0-rc.1)
#   AX_SERVER_IMAGE       ax-server image (default: the v0.4.0-rc.1 release digest)
#   AX_RUNNER_VOLUME_IMAGE Runner volume image (default: the v0.4.0-rc.1 release digest)
#   BENCH_NAME            Local cluster name (default ax-bench)
#   CONTAINER_CONNECTION  Podman connection; ax local rejects rootless Podman, so
#                         use the machine's rootful one, e.g. podman-machine-default-root
#   BENCH_KEEP=1          Leave the cluster running at the end
set -uo pipefail

: "${BENCH_DIR:?set BENCH_DIR to an output directory}"
AX_VERSION="${AX_VERSION:-v0.4.0-rc.1}"
NAME="${BENCH_NAME:-ax-bench}"
CTX="kind-${NAME}"
mkdir -p "$BENCH_DIR"
BENCH_DIR="$(cd "$BENCH_DIR" && pwd)"
LOGS="$BENCH_DIR/logs"
mkdir -p "$LOGS"

export KUBECONFIG="$BENCH_DIR/kubeconfig" AX_HOME="$BENCH_DIR/axhome"
export AX_SERVER_IMAGE="${AX_SERVER_IMAGE:-ghcr.io/google/ax/ax-server@sha256:95737151ccc54fdb8d99a8a8674f11777d7b08b7108a7b80820a1c502bb71223}"
export AX_RUNNER_VOLUME_IMAGE="${AX_RUNNER_VOLUME_IMAGE:-ghcr.io/google/ax/ax-runner-volume@sha256:ac849f8357ac5b412d2d35d9076ef94b00557399d95c52c62353954e2101be07}"

if [[ -z "${AX_BIN:-}" ]]; then
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  arch="$(uname -m)"; [[ "$arch" == "x86_64" ]] && arch=amd64; [[ "$arch" == "aarch64" ]] && arch=arm64
  tarball="ax_${os}_${arch}.tar.gz"
  if [[ ! -x "$BENCH_DIR/bin/ax" ]]; then
    mkdir -p "$BENCH_DIR/bin"
    gh release download "$AX_VERSION" --repo google/ax --clobber \
      --pattern "$tarball" --pattern checksums.txt --dir "$BENCH_DIR" || exit 1
    (cd "$BENCH_DIR" && grep " ${tarball}\$" checksums.txt | shasum -a 256 -c -) || exit 1
    tar -xzf "$BENCH_DIR/$tarball" -C "$BENCH_DIR/bin" ax || exit 1
  fi
  AX_BIN="$BENCH_DIR/bin/ax"
fi
"$AX_BIN" local --help > /dev/null 2>&1 || { echo "$AX_BIN has no 'ax local'" >&2; exit 1; }

stamp() {
  python3 -u -c '
import sys, time
t0 = time.time()
for line in sys.stdin:
    print(f"{time.time() - t0:8.2f}s  {line}", end="", flush=True)
'
}

monitor() {
  local out="$1" t0
  t0=$(date +%s)
  while :; do
    {
      echo "### t=$(($(date +%s) - t0))s"
      kubectl --context "$CTX" --request-timeout=5s get pods -A --no-headers \
        -o custom-columns='NS:.metadata.namespace,POD:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[*].ready,RESTARTS:.status.containerStatuses[*].restartCount,WAITING:.status.containerStatuses[*].state.waiting.reason,INIT:.status.initContainerStatuses[*].state.waiting.reason' 2>&1
    } >> "$out"
    sleep 10
  done
}

events() {
  kubectl --context "$CTX" get events -A --sort-by=.lastTimestamp \
    -o custom-columns='TIME:.lastTimestamp,NS:.metadata.namespace,OBJ:.involvedObject.name,REASON:.reason,COUNT:.count,MSG:.message' \
    > "$1" 2>&1
}

# phase <label> <watch:0|1> <ax local args...>
phase() {
  local label="$1" watch="$2" s e rc mon=""
  shift 2
  echo "=== $label: ax local $*" | tee -a "$LOGS/summary.txt"
  if [[ "$watch" == 1 ]]; then monitor "$LOGS/$label.pods.log" & mon=$!; fi
  s=$(python3 -c 'import time; print(time.time())')
  "$AX_BIN" local "$@" 2>&1 | stamp | tee "$LOGS/$label.log"
  rc=${PIPESTATUS[0]}
  e=$(python3 -c 'import time; print(time.time())')
  if [[ -n "$mon" ]]; then kill "$mon" 2>/dev/null; events "$LOGS/$label.events.txt"; fi
  printf '=== %s: exit=%s wall=%.1fs\n' "$label" "$rc" "$(python3 -c "print($e - $s)")" | tee -a "$LOGS/summary.txt"
  return "$rc"
}

: > "$LOGS/summary.txt"
"$AX_BIN" version | tee -a "$LOGS/summary.txt"
"$AX_BIN" local delete --name "$NAME" > /dev/null 2>&1

phase 1-cold-start 1 start --name "$NAME" || exit 1
phase 2-status 0 status --name "$NAME"
phase 3-stop 0 stop --name "$NAME"
phase 4-resume 1 start --name "$NAME"
phase 5-delete 0 delete --name "$NAME"
phase 6-recreate 1 start --name "$NAME"
if [[ "${BENCH_KEEP:-0}" != 1 ]]; then
  phase 7-delete 0 delete --name "$NAME"
fi
echo "Logs: $LOGS"
