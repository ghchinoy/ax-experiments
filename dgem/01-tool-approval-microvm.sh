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

# Recipe 01: Genkit Go v1.14.0 systemonex.SystemOne + ToolApproval Interrupt
# Guardrail inside an Apple container microVM on macOS (ate-local).

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${DIR}/ensure-stack.sh"
source "${DIR}/../swarm/lib.sh"

ensure_dgem_stack
require_tools
ensure_dgem_task_image

TASK_NAME="dgem-genkit-client"
TMP_MANIFEST="$(mktemp "${TMPDIR:-/tmp}/dgem-client-XXXXXX.yaml")"
trap 'rm -f "${TMP_MANIFEST}"; delete_tasks "${TASK_NAME}"' EXIT

cat > "${TMP_MANIFEST}" <<EOF
apiVersion: ax.io/v1alpha1
kind: Task
metadata:
  name: ${TASK_NAME}
  atespace: default
spec:
  image: "dgem-genkit-task:latest"
  debug: true
  env:
    - name: DGEM_GATEWAY_URL
      value: "${DGEM_GATEWAY_URL}"
    - name: DGEM_BACKEND
      value: "${DGEM_BACKEND}"
    - name: DGEM_MODEL
      value: "diffgemma-26b-a4b-it-q4"
EOF

echo "==> Applying & resuming AX Task ${TASK_NAME}..."
apply_task "${TMP_MANIFEST}"
resume_task "${TASK_NAME}"
wait_ready "${TASK_NAME}" 30
"${AX_BIN}" describe task "${TASK_NAME}"

echo
echo "==> Running genkit-tool-approval inside Apple container microVM..."
ssh_task "${TASK_NAME}" sh -c '
  echo "=== Guest Kernel: $(uname -sm) | IP: $(hostname -I) ==="
  genkit-tool-approval -templates /opt/dgem/templates
'

echo
echo "==> Running genkit-bulk-synth (github_spam_triage, 6 items) inside Apple container microVM..."
ssh_task "${TASK_NAME}" genkit-bulk-synth -curated -count 6 -workers 1 -templates /opt/dgem/templates
