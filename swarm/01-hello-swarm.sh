#!/usr/bin/env bash
# Recipe 01: Hello Swarm — 8 Parallel Tasks reporting isolation and vmnet IPs
# No API key required.

set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${DIR}/lib.sh"
require_tools

SWARM_SIZE=8
TASKS=()
for i in $(seq 0 $((SWARM_SIZE - 1))); do
  TASKS+=("hello-node-${i}")
done

echo "==> [01 Hello Swarm] Spawning ${SWARM_SIZE} parallel tasks on Apple Container..."
T_START=$SECONDS
trace_start "01-hello-swarm" "fan-out" "${SWARM_SIZE}"

TMP_MANIFEST="$(mktemp /tmp/hello-swarm-XXXXXX.yaml)"
trap 'rm -f "${TMP_MANIFEST}"; delete_tasks "${TASKS[@]}"' EXIT

# Generate multi-document Task manifest
for t in "${TASKS[@]}"; do
  trace_node_add "$t" "worker" "$t"
  cat >>"${TMP_MANIFEST}" <<EOF
apiVersion: ax.io/v1alpha1
kind: Task
metadata:
  name: ${t}
  atespace: default
spec:
  image: "debian:12"
  debug: true
---
EOF
done

echo "--> Applying and resuming ${SWARM_SIZE} tasks..."
apply_task "${TMP_MANIFEST}"

for t in "${TASKS[@]}"; do
  resume_task "$t" &
done
wait

echo "--> Waiting for all ${SWARM_SIZE} microVMs to report Ready on vmnet..."
wait_all_ready 45 "${TASKS[@]}"
T_READY=$SECONDS

echo
printf "%-18s %-16s %-24s %s\n" "TASK NAME" "WORKER IP" "HOSTNAME" "OS / ARCH"
printf "%-18s %-16s %-24s %s\n" "---------" "---------" "--------" "---------"

for t in "${TASKS[@]}"; do
  desc="$("${AX_BIN}" describe task "$t" 2>/dev/null)"
  ip="$(echo "${desc}" | awk '/Worker IP:/{print $3}')"
  info="$(ssh_task "$t" sh -c 'printf "%s|%s" "$(hostname)" "$(uname -sm)"' 2>/dev/null || echo "error|error")"
  hname="$(echo "${info}" | cut -d'|' -f1)"
  arch="$(echo "${info}" | cut -d'|' -f2)"
  printf "%-18s %-16s %-24s %s\n" "$t" "$ip" "$hname" "$arch"
done

T_TOTAL=$((SECONDS - T_START))
trace_end "01-hello-swarm" "success" "${T_TOTAL}"
echo
echo "==> Swarm completed in ${T_TOTAL}s (provisioned and ready in $((T_READY - T_START))s)."
echo "==> Cleaning up swarm containers..."
delete_tasks "${TASKS[@]}"
echo "==> Done."
