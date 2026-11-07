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

# Recipe 02: Declarative Genkit Go Runner (#538) + dgem Streamable HTTP MCP
# inside an Apple container microVM on macOS (ate-local).

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${DIR}/ensure-stack.sh"
source "${DIR}/../swarm/lib.sh"

if [[ -z "${GEMINI_API_KEY:-}" ]]; then
  echo "Error: GEMINI_API_KEY environment variable is required." >&2
  exit 1
fi

ensure_dgem_stack
require_tools
ensure_genkit_runner

TASK_NAME="dgem-mcp-agent"
WS_NAME="dgem-triage-ws"
TMP_MANIFEST="$(mktemp "${TMPDIR:-/tmp}/dgem-mcp-XXXXXX.yaml")"
trap 'rm -f "${TMP_MANIFEST}"; delete_tasks "${TASK_NAME}"; "${AX_BIN}" delete workspace "${WS_NAME}" >/dev/null 2>&1 || true; restore_default_runner' EXIT

cat > "${TMP_MANIFEST}" <<EOF
apiVersion: ax.io/v1alpha1
kind: Workspace
metadata:
  name: ${WS_NAME}
  atespace: default
spec:
  files:
    - path: "inbox/ticket-9481.txt"
      content: |
        Double charged \$500 on invoice #9481 for my annual renewal this morning — please refund ASAP!
  mcp:
    servers:
      - name: dgem
        endpoint: "${DGEM_MCP_URL}"
---
apiVersion: ax.io/v1alpha1
kind: Task
metadata:
  name: ${TASK_NAME}
  atespace: default
spec:
  image: "ax-agent-local:latest"
  config:
    name: dgem_triage_agent
    description: Uses local M5 DiffusionGemma policy templates via MCP to triage incoming tickets.
    model: googleai/gemini-3.8-flash
    instruction: |
      You are an operations triage agent running inside an AX Apple container microVM.
      Use the filesystem tools to read /workspace/inbox/ticket-9481.txt, then call
      the dgem MCP tool (dgem_decide_policy) with template_id="support_triage",
      backend="${DGEM_BACKEND}", and the ticket variable, and write a concise markdown report
      of the decision and probabilities to /workspace/DECISION_REPORT.md.
    config:
      maxOutputTokens: 2048
      temperature: 0.2
    maxTurns: 8
    use:
      - name: genkit-middleware/filesystem
        config:
          rootDirectory: /workspace
          allowWriteAccess: true
  env:
    - name: GEMINI_API_KEY
      value: "${GEMINI_API_KEY}"
  workspace:
    name: ${WS_NAME}
  debug: true
EOF

echo "==> [1/4] Applying Workspace (${WS_NAME}) and Task (${TASK_NAME})..."
apply_task "${TMP_MANIFEST}"

echo "==> [2/4] Resuming ${TASK_NAME} in Apple container microVM..."
resume_task "${TASK_NAME}"
wait_ready "${TASK_NAME}" 30
WORKER_IP="$(task_ip "${TASK_NAME}")"
wait_a2a_ready "${WORKER_IP}" 15
echo "    MicroVM ready at ${WORKER_IP}"
curl -fsSL "http://${WORKER_IP}:80/.well-known/agent-card.json" | jq .

echo
echo "==> [3/4] Sending A2A message/send request to http://${WORKER_IP}:80/..."
curl -fsSL -H "Content-Type: application/json" "http://${WORKER_IP}:80/" -d "{
  \"jsonrpc\": \"2.0\", \"id\": 1, \"method\": \"message/send\",
  \"params\": {\"message\": {\"role\": \"user\", \"messageId\": \"m1\", \"contextId\": \"ticket-9481\",
    \"parts\": [{\"kind\": \"text\", \"text\": \"Read /workspace/inbox/ticket-9481.txt, evaluate it using the dgem support_triage policy template (with backend=\\\"${DGEM_BACKEND}\\\"), and write the results to /workspace/DECISION_REPORT.md.\"}]}}
}" | jq .

echo
echo "==> [4/4] Inspecting /workspace/DECISION_REPORT.md inside microVM via ax ssh..."
ssh_task "${TASK_NAME}" cat /workspace/DECISION_REPORT.md
