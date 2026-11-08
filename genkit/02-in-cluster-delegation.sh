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

# Example 02: Autonomous In-Cluster Agent-to-Agent Delegation
# (Genkit MCP -> In-Sandbox A2A gRPC -> atenet-router:443 Wake-on-Request)
#
# Architecture (see genkit/CONCEPTS_BRIEF.md):
#   - `security-specialist`: Genkit task with a webhook security rubric skill,
#     left in the `Suspended` phase (0 active workers).
#   - `lead-engineer`: Coordinator Genkit task whose Workspace declares an
#     in-sandbox stdio MCP server (`/usr/local/bin/a2a-mcp-bridge`).
#   - When the host sends a SINGLE A2A gRPC `SendStreamingMessage` request to
#     `lead-engineer`, its Genkit tool loop calls the MCP tool
#     `delegate_to_actor(actor="security-specialist", ...)`, which dials
#     `atenet-router.ate-system.svc.cluster.local:443` over mTLS from INSIDE
#     the gVisor sandbox, wakes `security-specialist` on-demand, receives its
#     A2A gRPC audit, patches `/workspace/webhook_handler.go`, and logs
#     telemetry to `/workspace/.genkit/mcp-delegation.jsonl`.

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
ROUTER_TLS_CACHE="${HOME}/.ax/tunnels/${KUBE_CONTEXT:-kind-ax-e2e}-${AX_SYSTEM_NAMESPACE:-ax-system}-ax-server-router-tls.json"

ax() { "${AX_BIN}" "$@"; }

printf '\n==> [1/6] Building a2a-mcp-bridge and packaging into localhost:5001/genkit-runner...\n'
mkdir -p "${AX_REPO}/bin/linux_amd64"
(
  cd "${SCRIPT_DIR}"
  CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags="-s -w" \
    -o "${AX_REPO}/bin/linux_amd64/a2a-mcp-bridge" ./cmd/a2a-mcp-bridge
)
(
  cd "${AX_REPO}"
  CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags="-s -w" \
    -o bin/linux_amd64/genkit-runner ./cmd/runners/genkit-runner
  TMP_DOCKERFILE="$(mktemp "${AX_REPO}/.Dockerfile.genkit-mcp.XXXXXX")"
  cat <<'DOCKERFILE' > "${TMP_DOCKERFILE}"
FROM localhost:5001/ax-task-runner:e2e
COPY bin/linux_amd64/genkit-runner /usr/local/bin/ax-task-runner
COPY bin/linux_amd64/a2a-mcp-bridge /usr/local/bin/a2a-mcp-bridge
ENTRYPOINT ["/usr/local/bin/ax-task-runner"]
DOCKERFILE
  docker build -q -t localhost:5001/genkit-runner:latest -f "${TMP_DOCKERFILE}" . >/dev/null
  rm -f "${TMP_DOCKERFILE}"
  docker push -q localhost:5001/genkit-runner:latest >/dev/null
  docker image inspect --format '{{range .RepoDigests}}{{println .}}{{end}}' localhost:5001/genkit-runner:latest |
    grep '^localhost:5001/genkit-runner@' | head -n1 | sed 's/.*@//' > bin/genkit-runner.digest
)
GENKIT_DIGEST="$(cat "${AX_REPO}/bin/genkit-runner.digest")"
GENKIT_IMAGE="localhost:5001/genkit-runner@${GENKIT_DIGEST}"
printf '  ✔ Pushed image: %s\n' "${GENKIT_IMAGE}"

TMP_MANIFEST="$(mktemp /tmp/ax-in-cluster-delegation-XXXXXX.yaml)"
cleanup() {
  rm -f "${TMP_MANIFEST}"
  ax delete task lead-engineer -a "${ATESPACE}" >/dev/null 2>&1 || true
  ax delete task security-specialist -a "${ATESPACE}" >/dev/null 2>&1 || true
  ax delete workspace lead-ws -a "${ATESPACE}" >/dev/null 2>&1 || true
  ax delete workspace specialist-ws -a "${ATESPACE}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

printf '\n==> [2/6] Cleaning up any prior lead-engineer / security-specialist resources...\n'
cleanup
TMP_MANIFEST="$(mktemp /tmp/ax-in-cluster-delegation-XXXXXX.yaml)"

ADC_INDENTED=""
if [[ -f "${ADC_PATH}" ]]; then
  ADC_INDENTED="$(sed 's/^/        /' "${ADC_PATH}")"
fi

# Ensure router mTLS cache exists on host
if [[ ! -f "${ROUTER_TLS_CACHE}" ]]; then
  echo "error: router TLS cache ${ROUTER_TLS_CACHE} not found; run ./demo.sh once first" >&2
  exit 1
fi
ROUTER_TLS_INDENTED="$(sed 's/^/        /' "${ROUTER_TLS_CACHE}")"

cat <<YAML > "${TMP_MANIFEST}"
apiVersion: ax.io/v1alpha1
kind: Workspace
metadata:
  name: specialist-ws
  atespace: ${ATESPACE}
spec:
  files:
    - path: ".agents/skills/webhook-security/SKILL.md"
      content: |
        ---
        name: webhook-security
        description: Security audit checklist for webhook signature verification and replay defense.
        ---
        # Webhook Security Audit Checklist
        1. Never compare HMAC signatures with \`==\`; always use \`hmac.Equal(a, b)\` for constant-time comparison to prevent timing side-channel attacks.
        2. Reject payloads missing an \`X-Webhook-Timestamp\` or older than 5 minutes to prevent replay attacks.
        3. Always write a short summary of your audit to \`SECURITY_AUDIT.md\` in \`/workspace\`.
    - path: ".gcloud/adc.json"
      content: |
${ADC_INDENTED}
  skills:
    path: ".agents/skills"
---
apiVersion: ax.io/v1alpha1
kind: Workspace
metadata:
  name: lead-ws
  atespace: ${ATESPACE}
spec:
  files:
    - path: "webhook_handler.go"
      content: |
        package webhook

        import (
            "crypto/hmac"
            "crypto/sha256"
            "encoding/hex"
        )

        func VerifySignature(payload []byte, headerSig string, secret []byte) bool {
            mac := hmac.New(sha256.New, secret)
            mac.Write(payload)
            expected := hex.EncodeToString(mac.Sum(nil))
            // BUG: vulnerable to timing attack and no timestamp replay check
            return expected == headerSig
        }
    - path: ".ax-router-tls.json"
      content: |
${ROUTER_TLS_INDENTED}
    - path: ".gcloud/adc.json"
      content: |
${ADC_INDENTED}
  mcp:
    servers:
      - name: a2abridge
        command: "/usr/local/bin/a2a-mcp-bridge"
        args: ["--tls-file", "/workspace/.ax-router-tls.json"]
---
apiVersion: ax.io/v1alpha1
kind: Task
metadata:
  name: security-specialist
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
    name: specialist-ws
  config:
    name: security_specialist
    description: Security auditor that inspects Go webhook code for timing and replay vulnerabilities.
    model: "${MODEL}"
    instruction: |
      You are security_specialist. Load the webhook-security skill if needed.
      When given Go code, write a concise audit report to SECURITY_AUDIT.md using write_file
      (use ONLY write_file or read_file, no other tools) and reply with the exact vulnerabilities
      and corrected Go function.
    config:
      maxOutputTokens: 2048
      temperature: 0.1
    maxTurns: 6
    use:
      - name: genkit-middleware/filesystem
        config:
          allowWriteAccess: true
      - name: genkit-middleware/skills
---
apiVersion: ax.io/v1alpha1
kind: Task
metadata:
  name: lead-engineer
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
    name: lead-ws
  config:
    name: lead_engineer
    description: Lead engineer that delegates security audits to in-cluster specialist actors over A2A gRPC.
    model: "${MODEL}"
    instruction: |
      You are lead_engineer working in /workspace.
      Use ONLY your filesystem tools (list_files, read_file, write_file, edit_file) and your
      MCP tool (a2abridge_delegate_to_actor). Never call python_interpreter.
      Always delegate security review to actor="security-specialist" via a2abridge_delegate_to_actor
      before patching webhook_handler.go.
    config:
      maxOutputTokens: 2048
      temperature: 0.1
    maxTurns: 8
    use:
      - name: genkit-middleware/filesystem
        config:
          allowWriteAccess: true
YAML

printf '==> [3/6] Applying Workspaces and Tasks (lead-engineer + security-specialist)...\n'
ax apply -f "${TMP_MANIFEST}"

printf '\n==> [4/6] Provisioning actors, leaving security-specialist SUSPENDED, and verifying MCP tool registration...\n'
ax resume task security-specialist -a "${ATESPACE}"
ax suspend task security-specialist -a "${ATESPACE}"
ax resume task lead-engineer -a "${ATESPACE}"
ax get tasks -a "${ATESPACE}"

printf '\n--- [Verifying MCP tool registration in lead-engineer:/workspace/.genkit/prompts/lead_engineer.prompt] ---\n'
ax ssh lead-engineer -a "${ATESPACE}" -- cat /workspace/.genkit/prompts/lead_engineer.prompt

printf '\n==> [5/6] Running egm-orchestrator (--mode=in-cluster-delegation)...\n'
(
  cd "${SCRIPT_DIR}"
  go run ./cmd/egm-orchestrator \
    --mode in-cluster-delegation \
    --atespace "${ATESPACE}" \
    --ax-namespace "${AX_SYSTEM_NAMESPACE:-ax-system}" \
    --context "${KUBE_CONTEXT:-kind-ax-e2e}"
)

printf '\n==> [6/6] Inspecting in-sandbox delegation telemetry and artifacts across both sandboxes...\n'
ax get tasks -a "${ATESPACE}"

printf '\n--- [lead-engineer:/workspace/.genkit/mcp-delegation.jsonl (In-Sandbox A2A gRPC Telemetry)] ---\n'
ax ssh lead-engineer -a "${ATESPACE}" -- cat /workspace/.genkit/mcp-delegation.jsonl

printf '\n--- [lead-engineer:/workspace/webhook_handler.go] ---\n'
ax ssh lead-engineer -a "${ATESPACE}" -- cat /workspace/webhook_handler.go

printf '\n--- [lead-engineer:/workspace/DELEGATION_REPORT.md] ---\n'
ax ssh lead-engineer -a "${ATESPACE}" -- cat /workspace/DELEGATION_REPORT.md

printf '\n--- [security-specialist:/workspace/SECURITY_AUDIT.md] ---\n'
ax ssh security-specialist -a "${ATESPACE}" -- cat /workspace/SECURITY_AUDIT.md

printf '\n==> [Example 02] Autonomous In-Cluster Agent-to-Agent Delegation completed!\n'
