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

# Recipe 08: Declarative TaskSpec.config & Loopback Metadata Server (#479, #496, #523)
# Demonstrates:
#   1. Declaring structured agent configuration in Task.spec.config (google.protobuf.Struct)
#   2. Binding a single Workspace with inlined files (Task.spec.workspace)
#   3. Reading /metadata/v1alpha1/ax/task and /metadata/v1alpha1/ax/workspace from
#      the loopback-only metadata server (127.0.0.1:8099) inside the microVM
#   4. Verifying that port 80 on the container's bridge IP serves /readyz but blocks
#      external access to /metadata/v1alpha1/ax/task (returns 404).

set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${DIR}/lib.sh"
require_tools

TASK_NAME="config-inspector"
WS_NAME="config-ws"

echo "==> [08 Spec.Config & Loopback Metadata] Launching task with structured spec.config..."
T_START=$SECONDS

TMP_MANIFEST="$(mktemp /tmp/spec-config-XXXXXX.yaml)"
trap 'rm -f "${TMP_MANIFEST}"; delete_tasks "${TASK_NAME}"; "${AX_BIN}" delete workspace "${WS_NAME}" >/dev/null 2>&1 || true' EXIT

cat >"${TMP_MANIFEST}" <<EOF
apiVersion: ax.io/v1alpha1
kind: Workspace
metadata:
  name: ${WS_NAME}
  atespace: default
spec:
  files:
    - path: "policy/rules.json"
      content: |
        {"maxRetries": 3, "sandbox": "apple-container", "loopbackMetadata": true}
---
apiVersion: ax.io/v1alpha1
kind: Task
metadata:
  name: ${TASK_NAME}
  atespace: default
spec:
  image: "ax-agent-local:latest"
  debug: true
  workspace:
    name: ${WS_NAME}
  config:
    role: "Metadata & Security Verifier"
    model: "gemini-3.8-flash"
    maxTurns: 4
    tags:
      - "apple-container"
      - "loopback-metadata"
EOF

echo "--> Step 1: Applying Workspace and Task with spec.config..."
apply_task "${TMP_MANIFEST}"

echo "--> Step 2: Resuming Task and waiting for Ready..."
resume_task "${TASK_NAME}"
wait_ready "${TASK_NAME}" 45

echo
echo "--> Step 3: Inspecting 'ax describe task ${TASK_NAME}' (shows Config: section from #523)..."
"${AX_BIN}" describe task "${TASK_NAME}"

WORKER_IP="$("${AX_BIN}" describe task "${TASK_NAME}" | awk '/Worker IP:/{print $3}')"
echo
echo "--> Step 4: Verifying external boundary on ${WORKER_IP}:80..."
READY_CODE="$(curl -s -o /dev/null -w "%{http_code}" "http://${WORKER_IP}:80/readyz")"
META_EXTERNAL_CODE="$(curl -s -o /dev/null -w "%{http_code}" "http://${WORKER_IP}:80/metadata/v1alpha1/ax/task")"
echo "    GET http://${WORKER_IP}:80/readyz                  -> HTTP ${READY_CODE} (expected 200)"
echo "    GET http://${WORKER_IP}:80/metadata/v1alpha1/ax/task -> HTTP ${META_EXTERNAL_CODE} (expected 404; loopback-only!)"

echo
echo "--> Step 5: Querying loopback metadata server (127.0.0.1:8099) from INSIDE the microVM..."
ssh_task "${TASK_NAME}" sh -c '
  echo "--- [Inside Container] /metadata/v1alpha1/ax/task ---"
  curl -s http://127.0.0.1:8099/metadata/v1alpha1/ax/task
  echo "--- [Inside Container] /metadata/v1alpha1/ax/workspace ---"
  curl -s http://127.0.0.1:8099/metadata/v1alpha1/ax/workspace
  echo "--- [Inside Container] Materialized Workspace File (/workspace/policy/rules.json) ---"
  cat /workspace/policy/rules.json
'

T_TOTAL=$((SECONDS - T_START))
echo
echo "==> Spec.config and loopback metadata verification completed in ${T_TOTAL}s."
