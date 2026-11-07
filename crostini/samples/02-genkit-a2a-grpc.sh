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

# Sample 2: Multi-Agent Genkit Interaction (coder-agent <-> auditor-agent)
# over A2A gRPC Transport (lf.a2a.v1.A2AService) on Crostini Kind + Substrate
#
# Both tasks run the exact same `localhost:5001/genkit-runner` image and are
# defined purely via YAML (`Task.spec.config` Dotprompt). They converse across
# two isolated gVisor sandboxes over the A2A gRPC protocol routed through
# `atenet-router` with mTLS, including scale-to-zero (`ax suspend`) and
# wake-on-request over A2A gRPC.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AX_REPO="${AX_REPO:-${HOME}/projects/ax}"
if [[ -f "${AX_REPO}/.tmp/e2e.env" ]]; then
  # shellcheck disable=SC1090
  source "${AX_REPO}/.tmp/e2e.env"
fi
AX_BIN="${AX_BIN:-${AX_REPO}/.tmp/bin/ax}"
ATESPACE="${ATESPACE:-default}"
MODEL="${GENKIT_MODEL:-vertexai/gemini-2.5-flash}"
GCP_PROJECT="${GOOGLE_CLOUD_PROJECT:-generative-bazaar-001}"
ADC_PATH="${HOME}/.config/gcloud/application_default_credentials.json"

ax() { "${AX_BIN}" "$@"; }

if [[ ! -f "${AX_REPO}/bin/genkit-runner.digest" ]]; then
  printf '==> Building and pushing localhost:5001/genkit-runner image...\n'
  (
    cd "${AX_REPO}"
    make push-genkit-image \
      CONTAINER_CLI=docker \
      GENKIT_REPO=localhost:5001/genkit-runner \
      GENKIT_BASE_IMAGE=localhost:5001/ax-task-runner:e2e
  )
fi
GENKIT_DIGEST="$(cat "${AX_REPO}/bin/genkit-runner.digest")"
GENKIT_IMAGE="localhost:5001/genkit-runner@${GENKIT_DIGEST}"

if [[ -z "${GEMINI_API_KEY:-}" && ! -f "${ADC_PATH}" ]]; then
  echo "error: neither GEMINI_API_KEY nor ${ADC_PATH} is present" >&2
  exit 1
fi

TMP_MANIFEST="$(mktemp /tmp/ax-sample02-XXXXXX.yaml)"
cleanup() {
  rm -f "${TMP_MANIFEST}"
  ax delete task coder-agent -a "${ATESPACE}" >/dev/null 2>&1 || true
  ax delete task auditor-agent -a "${ATESPACE}" >/dev/null 2>&1 || true
  ax delete workspace coder-ws -a "${ATESPACE}" >/dev/null 2>&1 || true
  ax delete workspace auditor-ws -a "${ATESPACE}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

printf '\n==> [Sample 02] Cleaning up any prior coder-agent / auditor-agent resources...\n'
cleanup
TMP_MANIFEST="$(mktemp /tmp/ax-sample02-XXXXXX.yaml)"

ADC_INDENTED=""
if [[ -f "${ADC_PATH}" ]]; then
  ADC_INDENTED="$(sed 's/^/        /' "${ADC_PATH}")"
fi

cat <<YAML > "${TMP_MANIFEST}"
apiVersion: ax.io/v1alpha1
kind: Workspace
metadata:
  name: coder-ws
  atespace: ${ATESPACE}
spec:
  files:
    - path: "README.md"
      content: |
        # Payment Service (payd)
        Handles checkout authorization and settlement retries.

        ## Known Bug
        - \`TestRetryBackoff_ZeroJitter\` in \`retry_test.go\` panics when \`maxJitter <= 0\` because \`rand.Int63n(maxJitter)\` requires a strictly positive argument.
    - path: "retry_test.go"
      content: |
        package payd

        import (
            "math/rand"
            "testing"
        )

        func ComputeJitter(maxJitter int64) int64 {
            // BUG: panics when maxJitter <= 0
            return rand.Int63n(maxJitter)
        }

        func TestRetryBackoff_ZeroJitter(t *testing.T) {
            got := ComputeJitter(0)
            if got != 0 {
                t.Fatalf("ComputeJitter(0) = %d, want 0", got)
            }
        }
    - path: ".gcloud/adc.json"
      content: |
${ADC_INDENTED}
---
apiVersion: ax.io/v1alpha1
kind: Workspace
metadata:
  name: auditor-ws
  atespace: ${ATESPACE}
spec:
  files:
    - path: ".agents/skills/security-rubric/SKILL.md"
      content: |
        ---
        name: security-rubric
        description: Mandatory security and boundary review rubric for Go patches in payd.
        ---
        # payd Security & Boundary Review Rubric
        1. Verify that any PRNG bound check guards against both zero (\`0\`) AND negative (\`< 0\`) inputs (\`maxJitter <= 0\`).
        2. Require unit tests to cover both \`0\` and negative bounds (\`-5\`).
        3. Always write the audit verdict to \`AUDIT_VERDICT.md\` in the workspace.
    - path: ".gcloud/adc.json"
      content: |
${ADC_INDENTED}
  skills:
    path: ".agents/skills"
---
apiVersion: ax.io/v1alpha1
kind: Task
metadata:
  name: coder-agent
  atespace: ${ATESPACE}
spec:
  image: "${GENKIT_IMAGE}"
  debug: true
  env:
    - name: GOOGLE_CLOUD_PROJECT
      value: "${GCP_PROJECT}"
    - name: GOOGLE_CLOUD_LOCATION
      value: "global"
    - name: GOOGLE_APPLICATION_CREDENTIALS
      value: "/workspace/.gcloud/adc.json"
    - name: GEMINI_API_KEY
      value: "${GEMINI_API_KEY:-}"
  workspace:
    name: coder-ws
  config:
    name: coder_agent
    description: Go engineer that inspects and patches code in /workspace.
    model: "${MODEL}"
    instruction: |
      You are coder_agent, a pragmatic Go software engineer working in /workspace.
      Always use your filesystem tools (list_files, read_file, write_file, search_and_replace)
      to read and update files in your workspace. Keep responses concise.
    config:
      maxOutputTokens: 2048
      temperature: 0.2
    maxTurns: 10
    use:
      - name: genkit-middleware/filesystem
        config:
          allowWriteAccess: true
---
apiVersion: ax.io/v1alpha1
kind: Task
metadata:
  name: auditor-agent
  atespace: ${ATESPACE}
spec:
  image: "${GENKIT_IMAGE}"
  debug: true
  env:
    - name: GOOGLE_CLOUD_PROJECT
      value: "${GCP_PROJECT}"
    - name: GOOGLE_CLOUD_LOCATION
      value: "global"
    - name: GOOGLE_APPLICATION_CREDENTIALS
      value: "/workspace/.gcloud/adc.json"
    - name: GEMINI_API_KEY
      value: "${GEMINI_API_KEY:-}"
  workspace:
    name: auditor-ws
  config:
    name: auditor_agent
    description: Security and reliability auditor that reviews patches against the security-rubric skill.
    model: "${MODEL}"
    instruction: |
      You are auditor_agent, a security and reliability code reviewer.
      Load the security-rubric skill if available, write your audit report to AUDIT_VERDICT.md
      using write_file, and return clear, concise review feedback.
    config:
      maxOutputTokens: 2048
      temperature: 0.2
    maxTurns: 10
    use:
      - name: genkit-middleware/filesystem
        config:
          allowWriteAccess: true
      - name: genkit-middleware/skills
YAML

printf '==> [1/4] Applying coder-ws, auditor-ws, coder-agent, and auditor-agent...\n'
ax apply -f "${TMP_MANIFEST}"

printf '\n==> [2/4] Resuming coder-agent and auditor-agent on gVisor workers...\n'
ax resume task coder-agent -a "${ATESPACE}"
ax resume task auditor-agent -a "${ATESPACE}"
ax get tasks -a "${ATESPACE}"

# Ensure the router mTLS certificate cache (~/.ax/tunnels/...-router-tls.json) is fresh
ax ssh coder-agent -a "${ATESPACE}" -- true

printf '\n==> [3/4] Running A2A gRPC orchestrator (crostini/samples/a2a-duo)...\n'
(
  cd "${SCRIPT_DIR}/a2a-duo"
  go build -o a2a-duo .
  ./a2a-duo \
    --atespace "${ATESPACE}" \
    --ax-namespace "${AX_SYSTEM_NAMESPACE:-ax-system}" \
    --context "${KUBE_CONTEXT:-kind-ax-e2e}" \
    --coder coder-agent \
    --auditor auditor-agent \
    --ax-bin "${AX_BIN}"
)

printf '\n==> [4/4] Inspecting artifacts inside both gVisor sandboxes via `ax ssh`...\n'
ax get tasks -a "${ATESPACE}"

printf '\n--- [coder-agent:/workspace/retry_test.go] ---\n'
ax ssh coder-agent -a "${ATESPACE}" -- cat /workspace/retry_test.go

printf '\n--- [coder-agent:/workspace/HANDOFF_COMPLETE.md] ---\n'
ax ssh coder-agent -a "${ATESPACE}" -- cat /workspace/HANDOFF_COMPLETE.md

printf '\n--- [auditor-agent:/workspace/AUDIT_VERDICT.md] ---\n'
ax ssh auditor-agent -a "${ATESPACE}" -- cat /workspace/AUDIT_VERDICT.md

printf '\n==> [Sample 02] Multi-agent A2A gRPC workflow completed successfully!\n'
