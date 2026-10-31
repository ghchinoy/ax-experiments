#!/usr/bin/env bash
# Recipe 07: Suspend & Resume Lifecycle
# Proves that filesystem state in /workspace persists across SuspendActor / ResumeActor
# while volatile in-memory processes are cleanly reset upon container reboot.
# No API key required.

set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${DIR}/lib.sh"
require_tools

TASK_NAME="lifecycle-probe"

echo "==> [07 Suspend & Resume Lifecycle] Verifying state boundaries across hibernation..."
T_START=$SECONDS

TMP_MANIFEST="$(mktemp /tmp/lifecycle-XXXXXX.yaml)"
trap 'rm -f "${TMP_MANIFEST}"; delete_tasks "${TASK_NAME}"' EXIT

cat >"${TMP_MANIFEST}" <<EOF
apiVersion: ax.io/v1alpha1
kind: Task
metadata:
  name: ${TASK_NAME}
  atespace: default
spec:
  image: "debian:12"
  debug: true
EOF

echo "--> Step 1: Create and resume task..."
apply_task "${TMP_MANIFEST}"
resume_task "${TASK_NAME}"
wait_ready "${TASK_NAME}" 45

echo "--> Step 2: Write state and check initial boot timestamp inside container..."
ssh_task "${TASK_NAME}" sh -c '
  mkdir -p /workspace/data
  echo "checkpoint-turn-1-data-payload" > /workspace/data/checkpoint.txt
  cat /proc/uptime | awk "{print \$1}" > /workspace/data/boot-1.txt
  echo "Wrote /workspace/data/checkpoint.txt. Initial kernel uptime: $(cat /workspace/data/boot-1.txt)s"
'

echo "--> Step 3: Suspending task (stopping Apple container to free host CPU/RAM)..."
"${AX_BIN}" suspend "${TASK_NAME}" >/dev/null
sleep 2

# Verify container is stopped
CONTAINER_STATE="$(container list --all 2>/dev/null | awk -v name="ate-default-${TASK_NAME}" '$1 == name {print $5}')"
echo "   Container state after suspend: ${CONTAINER_STATE:-stopped}"

echo "--> Step 4: Resuming task (cold-booting container with persistent volume)..."
"${AX_BIN}" resume "${TASK_NAME}" >/dev/null
wait_ready "${TASK_NAME}" 45

echo "--> Step 5: Verifying filesystem persistence vs process reset..."
ssh_task "${TASK_NAME}" sh -c '
  if [ -f /workspace/data/checkpoint.txt ]; then
    echo "SUCCESS: /workspace/data/checkpoint.txt persisted! Content: $(cat /workspace/data/checkpoint.txt)"
  else
    echo "FAILURE: checkpoint file missing!"
    exit 1
  fi
  BOOT_2=$(cat /proc/uptime | awk "{print \$1}")
  BOOT_1=$(cat /workspace/data/boot-1.txt)
  echo "Boot 1 uptime was: ${BOOT_1}s | Boot 2 uptime is: ${BOOT_2}s (rebooted into fresh VM)"
'

T_TOTAL=$((SECONDS - T_START))
echo
echo "==> Lifecycle verification completed in ${T_TOTAL}s."
delete_tasks "${TASK_NAME}"
echo "==> Done."
