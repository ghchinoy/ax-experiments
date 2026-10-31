#!/usr/bin/env bash
# Recipe 03: Fuzz & Seed Matrix — 6 parallel runs testing stochastic parameters
# No API key required.

set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${DIR}/lib.sh"
require_tools

SEEDS=(101 202 303 404 505 606)
TASKS=()
for s in "${SEEDS[@]}"; do
  TASKS+=("matrix-seed-${s}")
done

echo "==> [03 Seed Matrix] Running 6 parallel stochastic runs on Apple Container..."
T_START=$SECONDS

TMP_MANIFEST="$(mktemp /tmp/seed-matrix-XXXXXX.yaml)"
trap 'rm -f "${TMP_MANIFEST}"; delete_tasks "${TASKS[@]}"' EXIT

for s in "${SEEDS[@]}"; do
  cat >>"${TMP_MANIFEST}" <<EOF
apiVersion: ax.io/v1alpha1
kind: Task
metadata:
  name: matrix-seed-${s}
  atespace: default
spec:
  image: "debian:12"
  debug: true
  env:
    - name: SEED
      value: "${s}"
---
EOF
done

echo "--> Applying and resuming 6 matrix tasks..."
apply_task "${TMP_MANIFEST}"

for t in "${TASKS[@]}"; do
  resume_task "$t" &
done
wait

echo "--> Waiting for all 6 matrix tasks to be Ready..."
wait_all_ready 45 "${TASKS[@]}"

echo
printf "%-18s %-10s %-12s %s\n" "TASK" "SEED" "OUTCOME" "SIMULATION RESULT"
printf "%-18s %-10s %-12s %s\n" "----" "----" "-------" "-----------------"

for s in "${SEEDS[@]}"; do
  t="matrix-seed-${s}"
  # Run a deterministic hash/modulo simulation using the seed inside the microVM
  res="$(ssh_task "$t" sh -c 'calc=$(( ($SEED * 1103515245 + 12345) % 2147483648 )); if [ $((calc % 5)) -eq 0 ]; then echo "FAIL|edge case detected: remainder 0"; else echo "PASS|val=$calc"; fi' 2>/dev/null || echo "ERROR|ssh failed")"
  status="$(echo "${res}" | cut -d'|' -f1)"
  detail="$(echo "${res}" | cut -d'|' -f2)"
  printf "%-18s %-10s %-12s %s\n" "$t" "$s" "$status" "$detail"
done

T_TOTAL=$((SECONDS - T_START))
echo
echo "==> Matrix run completed in ${T_TOTAL}s."
delete_tasks "${TASKS[@]}"
echo "==> Done."
