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

# End-to-end verification of genkit-runner (#538) running inside an Apple
# container microVM on macOS via ate-local (#526):
#   1. Cross-compiles cmd/runners/genkit-runner (from origin/feat/genkit-runner)
#      for linux/arm64 and installs it into .ax-local/bin/linux_arm64/ax-task-runner.
#   2. Applies genkit/workspace.yaml (inline files + incident-runbook skill +
#      stdio MCP server tools/incident_mcp.py) and genkit/task-apple-container.yaml.
#   3. Resumes the task into an Apple container microVM and verifies
#      /.well-known/agent-card.json over the container's vmnet bridge IP.
#   4. Sends Turn 1 via A2A JSON-RPC (contextId: "incident-42"), exercising
#      MCP tool discovery (telemetry_get_active_incident), filesystem edits,
#      and TRIAGE_REPORT.md generation.
#   5. Suspends (stopping the microVM) and resumes (cold-booting a fresh microVM),
#      then sends Turn 2 over A2A and Turn 3 over Genkit HTTP (/agents/triage_agent)
#      to verify /workspace/.genkit/snapshots session durability across reboots.

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AX_REPO="${AX_REPO:-$HOME/projects/ax}"
STATE_DIR="${AX_LOCAL_DIR:-${AX_REPO}/.ax-local}"
AX_BIN="${AX_BIN:-${STATE_DIR}/bin/ax}"
RUNNER_TARGET="${STATE_DIR}/bin/linux_arm64/ax-task-runner"
AX_SERVER="${AX_SERVER:-127.0.0.1:8090}"
export AX_SERVER

if [[ -z "${GEMINI_API_KEY:-}" ]]; then
  echo "Error: GEMINI_API_KEY environment variable is required." >&2
  exit 1
fi

if [[ ! -x "${AX_BIN}" ]] || ! "${AX_BIN}" get tasks >/dev/null 2>&1; then
  cat >&2 <<EOF
Error: Cannot reach ax-server at ${AX_SERVER} (or ax binary missing at ${AX_BIN}).

Start the local AX + ate-local stack first:
  make stack-up

Or from your ax checkout (${AX_REPO}, branch feat/ate-local-apple-container):
  cd ${AX_REPO} && make local-up
EOF
  exit 1
fi

# Cross-compile genkit-runner for linux/arm64 from origin/feat/genkit-runner if not already built
GENKIT_CACHE="${STATE_DIR}/bin/linux_arm64/genkit-runner"
if [[ ! -x "${GENKIT_CACHE}" ]]; then
  echo "==> [0/6] Cross-compiling genkit-runner (linux/arm64) from origin/feat/genkit-runner..."
  WT_DIR="$(mktemp -d /tmp/ax-genkit-wt-XXXXXX)"
  (
    cd "${AX_REPO}"
    git worktree add --detach "${WT_DIR}" origin/feat/genkit-runner >/dev/null 2>&1
    trap 'git -C "${AX_REPO}" worktree remove --force "${WT_DIR}" >/dev/null 2>&1 || true' EXIT
    cd "${WT_DIR}"
    GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o "${GENKIT_CACHE}" ./cmd/runners/genkit-runner
  )
fi
cp "${GENKIT_CACHE}" "${RUNNER_TARGET}"

TMP_MANIFEST="$(mktemp /tmp/genkit-task-XXXXXX.yaml)"
trap 'rm -f "${TMP_MANIFEST}"; "${AX_BIN}" delete task genkit-triage >/dev/null 2>&1 || true; "${AX_BIN}" delete workspace demo-workspace >/dev/null 2>&1 || true' EXIT

sed "s|\${GEMINI_API_KEY}|${GEMINI_API_KEY}|g" "${DIR}/task-apple-container.yaml" > "${TMP_MANIFEST}"

echo "==> [1/6] Applying Workspace (demo-workspace) and Task (genkit-triage)..."
"${AX_BIN}" apply -f "${DIR}/workspace.yaml"
"${AX_BIN}" apply -f "${TMP_MANIFEST}"

echo "==> [2/6] Resuming genkit-triage in Apple container microVM..."
"${AX_BIN}" resume genkit-triage

WORKER_IP="$("${AX_BIN}" describe task genkit-triage | awk '/Worker IP:/{print $3}')"
echo "    Task Running at vmnet IP: ${WORKER_IP}"
"${AX_BIN}" describe task genkit-triage

echo
echo "==> [3/6] Fetching A2A Agent Card (http://${WORKER_IP}:80/.well-known/agent-card.json)..."
curl -fsSL "http://${WORKER_IP}:80/.well-known/agent-card.json" | jq .

echo
echo "==> [4/6] Turn 1 (A2A JSON-RPC, contextId=incident-42): Triage & Fix..."
curl -fsSL -H "Content-Type: application/json" "http://${WORKER_IP}:80/" -d '{
  "jsonrpc": "2.0", "id": 1, "method": "message/send",
  "params": {"message": {"role": "user", "messageId": "m1", "contextId": "incident-42",
    "parts": [{"kind": "text", "text": "Call get_active_incident if available, inspect the workspace files, fix the bug in retry_test.go, and write a brief summary to TRIAGE_REPORT.md."}]}}
}' | jq .

echo
echo "--- Verifying modified files inside microVM via ax ssh ---"
"${AX_BIN}" ssh genkit-triage -- sh -c '
  echo "=== /workspace/retry_test.go ==="
  cat /workspace/retry_test.go
  echo "=== /workspace/TRIAGE_REPORT.md ==="
  cat /workspace/TRIAGE_REPORT.md
  echo "=== /workspace/.genkit/snapshots ==="
  ls -la /workspace/.genkit/snapshots/
'

echo
echo "==> [5/6] Suspending and Resuming Task (microVM stop -> cold boot)..."
"${AX_BIN}" suspend genkit-triage
"${AX_BIN}" get tasks
"${AX_BIN}" resume genkit-triage
WORKER_IP="$("${AX_BIN}" describe task genkit-triage | awk '/Worker IP:/{print $3}')"
echo "    Task Resumed at vmnet IP: ${WORKER_IP}"

for _ in $(seq 1 30); do
  if curl -fsSL "http://${WORKER_IP}:80/.well-known/agent-card.json" >/dev/null 2>&1; then
    break
  fi
  sleep 0.2
done

echo
echo "==> [6/6] Turn 2 (A2A) & Turn 3 (Genkit HTTP /agents/triage_agent) after microVM reboot..."
curl -fsSL -H "Content-Type: application/json" "http://${WORKER_IP}:80/" -d '{
  "jsonrpc": "2.0", "id": 2, "method": "message/send",
  "params": {"message": {"role": "user", "messageId": "m2", "contextId": "incident-42",
    "parts": [{"kind": "text", "text": "Without reading any files again, what file did you fix in our previous turn and what was the second known issue mentioned in README.md?"}]}}
}' | jq .

echo
curl -fsSL -H "Content-Type: application/json" "http://${WORKER_IP}:80/agents/triage_agent" -d '{
  "data": {"message": {"role": "user", "content": [{"text": "Reply in one sentence confirming how many user turns we have had in this session across the suspend/resume."}]}},
  "init": {"sessionId": "incident-42"}
}' | jq .

echo
echo "==> Genkit Go Runner on Apple Container verification completed!"
