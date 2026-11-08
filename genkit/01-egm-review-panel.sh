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

# Example 01: Sandboxed Elephant-Goldfish Model (EGM) Design & Review Loop
# on AX + Agent Substrate over A2A gRPC (SendStreamingMessage)
#
# Architecture (see genkit/CONCEPTS_BRIEF.md):
#   - 1 Stateful Elephant Task (`elephant-architect`, allowWriteAccess: true,
#     persistent session contextId="elephant-session-1" in /workspace/.genkit/snapshots)
#   - 3 Stateless Goldfish Tasks (`goldfish-design`, `goldfish-catalyst`,
#     `goldfish-comprehension`, allowWriteAccess: false, mounting reviewer
#     personas from ~/projects/elephant-goldfish-model/agents/*.md into
#     .agents/skills/<persona>/SKILL.md and using Dotprompt output.schema)
#   - Residency Inversion: After Elephant drafts /workspace/DESIGN_SPEC.md in
#     Turn 1, the Elephant suspends (`ax suspend`) so all 3 gVisor workers run
#     the 3 Goldfish reviewers concurrently over A2A gRPC SendStreamingMessage.
#     Each Goldfish suspends immediately upon stream completion, and
#     atenet-router wakes the Elephant on-demand for Turn 2 resolution.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AX_REPO="${AX_REPO:-${HOME}/projects/ax}"
EGM_REPO="${EGM_REPO:-${HOME}/projects/elephant-goldfish-model}"
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
k() { kubectl --kubeconfig "${KUBECONFIG}" --context "${KUBE_CONTEXT}" "$@"; }

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

printf '\n==> [Pre-flight] Ensuring ax-workers has 3 gVisor replicas for 3-way parallel Goldfish wave...\n'
k -n "${AX_SYSTEM_NAMESPACE:-ax-system}" scale deployment/ax-workers --replicas=3
k -n "${AX_SYSTEM_NAMESPACE:-ax-system}" rollout status deployment/ax-workers --timeout=120s

TMP_MANIFEST="$(mktemp /tmp/ax-egm-panel-XXXXXX.yaml)"
cleanup() {
  rm -f "${TMP_MANIFEST}"
  for t in elephant-architect goldfish-design goldfish-catalyst goldfish-comprehension; do
    ax delete task "${t}" -a "${ATESPACE}" >/dev/null 2>&1 || true
  done
  for w in elephant-ws goldfish-design-ws goldfish-catalyst-ws goldfish-comprehension-ws; do
    ax delete workspace "${w}" -a "${ATESPACE}" >/dev/null 2>&1 || true
  done
}
trap cleanup EXIT

printf '\n==> [1/5] Cleaning up any prior EGM panel tasks and workspaces...\n'
cleanup
TMP_MANIFEST="$(mktemp /tmp/ax-egm-panel-XXXXXX.yaml)"

ADC_INDENTED=""
if [[ -f "${ADC_PATH}" ]]; then
  ADC_INDENTED="$(sed 's/^/        /' "${ADC_PATH}")"
fi

# Helper to load and indent a persona skill from ~/projects/elephant-goldfish-model/agents/
load_persona_skill() {
  local file="$1"
  local fallback_name="$2"
  local fallback_desc="$3"
  if [[ -f "${EGM_REPO}/agents/${file}" ]]; then
    sed 's/^/        /' "${EGM_REPO}/agents/${file}"
  else
    cat <<EOF
        ---
        name: ${fallback_name}
        description: ${fallback_desc}
        ---
        # ${fallback_name}
        ${fallback_desc}
EOF
  fi
}

DESIGN_SKILL="$(load_persona_skill "design_critic.md" "egm-design" "Hostile Design Critic persona focused on scalability, quota economics, and unmitigated failure modes.")"
CATALYST_SKILL="$(load_persona_skill "inventive_catalyst.md" "egm-inventive-catalyst" "Inventive Catalyst persona applying TRIZ principles to identify and resolve technical contradictions.")"
COMPREHENSION_SKILL="$(load_persona_skill "comprehension.md" "egm-comprehension" "Naive Reader persona auditing documents for undefined concepts, missing prerequisites, and ambiguity.")"

cat <<YAML > "${TMP_MANIFEST}"
apiVersion: ax.io/v1alpha1
kind: Workspace
metadata:
  name: elephant-ws
  atespace: ${ATESPACE}
spec:
  files:
    - path: "CONTEXT.md"
      content: |
        # Project Context: AX Webhook Delivery Subsystem
        We need to add outbound webhook delivery to AX so external systems receive
        notifications when a Task transitions between Running, Suspended, and Failed.
        Requirements to address in DESIGN_SPEC.md:
        - Event payload format and delivery endpoint registration
        - Handling downstream 5xx timeouts and duplicate events
        - Multi-tenant isolation across atespaces
    - path: ".gcloud/adc.json"
      content: |
${ADC_INDENTED}
---
apiVersion: ax.io/v1alpha1
kind: Workspace
metadata:
  name: goldfish-design-ws
  atespace: ${ATESPACE}
spec:
  files:
    - path: ".agents/skills/egm-design/SKILL.md"
      content: |
${DESIGN_SKILL}
    - path: ".gcloud/adc.json"
      content: |
${ADC_INDENTED}
  skills:
    path: ".agents/skills"
---
apiVersion: ax.io/v1alpha1
kind: Workspace
metadata:
  name: goldfish-catalyst-ws
  atespace: ${ATESPACE}
spec:
  files:
    - path: ".agents/skills/egm-inventive-catalyst/SKILL.md"
      content: |
${CATALYST_SKILL}
    - path: ".gcloud/adc.json"
      content: |
${ADC_INDENTED}
  skills:
    path: ".agents/skills"
---
apiVersion: ax.io/v1alpha1
kind: Workspace
metadata:
  name: goldfish-comprehension-ws
  atespace: ${ATESPACE}
spec:
  files:
    - path: ".agents/skills/egm-comprehension/SKILL.md"
      content: |
${COMPREHENSION_SKILL}
    - path: ".gcloud/adc.json"
      content: |
${ADC_INDENTED}
  skills:
    path: ".agents/skills"
---
apiVersion: ax.io/v1alpha1
kind: Task
metadata:
  name: elephant-architect
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
    name: elephant-ws
  config:
    name: elephant_architect
    description: Stateful Elephant architect that holds project context and drafts/revises DESIGN_SPEC.md.
    model: "${MODEL}"
    instruction: |
      You are the Elephant Architect in the Elephant-Goldfish Model (EGM).
      You hold persistent project context across turns.
      Use ONLY the filesystem tools (list_files, read_file, write_file, edit_file) to read,
      draft, and revise DESIGN_SPEC.md and RESOLUTION_LOG.md in /workspace.
      Do NOT call python_interpreter or any tool other than list_files, read_file, write_file, or edit_file.
      Keep documents concise and concrete.
    config:
      maxOutputTokens: 4096
      temperature: 0.2
    maxTurns: 8
    use:
      - name: genkit-middleware/filesystem
        config:
          allowWriteAccess: true
---
apiVersion: ax.io/v1alpha1
kind: Task
metadata:
  name: goldfish-design
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
    name: goldfish-design-ws
  config:
    name: goldfish_design
    description: Stateless Design Critic Goldfish reviewer (scalability, quota, failure modes).
    model: "${MODEL}"
    instruction: |
      You are the Design Critic Goldfish (egm-design). Load your egm-design skill if needed.
      Critique the design draft for unmitigated failure modes, retry storms, and quota limits.
      Return ONLY valid JSON with fields: reviewer ("goldfish-design"), verdict ("NEEDS_WORK" or "APPROVED"),
      summary (1 sentence), and findings (array of 2 objects with severity, title, recommendation).
    config:
      maxOutputTokens: 2048
      temperature: 0.1
    maxTurns: 4
    output:
      format: json
      schema:
        reviewer: string
        verdict: string
        summary: string
        findings(array):
          severity: string
          title: string
          recommendation: string
    use:
      - name: genkit-middleware/skills
---
apiVersion: ax.io/v1alpha1
kind: Task
metadata:
  name: goldfish-catalyst
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
    name: goldfish-catalyst-ws
  config:
    name: goldfish_catalyst
    description: Stateless Inventive Catalyst Goldfish reviewer (TRIZ contradiction resolution).
    model: "${MODEL}"
    instruction: |
      You are the Inventive Catalyst Goldfish (egm-inventive-catalyst). Load your egm-inventive-catalyst skill if needed.
      Identify technical contradictions in the design draft (e.g. delivery durability vs. control-plane latency) and propose inventive software patterns.
      Return ONLY valid JSON with fields: reviewer ("goldfish-catalyst"), verdict ("NEEDS_WORK" or "APPROVED"),
      summary (1 sentence), and findings (array of 2 objects with severity, title, recommendation).
    config:
      maxOutputTokens: 2048
      temperature: 0.1
    maxTurns: 4
    output:
      format: json
      schema:
        reviewer: string
        verdict: string
        summary: string
        findings(array):
          severity: string
          title: string
          recommendation: string
    use:
      - name: genkit-middleware/skills
---
apiVersion: ax.io/v1alpha1
kind: Task
metadata:
  name: goldfish-comprehension
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
    name: goldfish-comprehension-ws
  config:
    name: goldfish_comprehension
    description: Stateless Comprehension Goldfish reviewer (naive reader clarity and undefined terms).
    model: "${MODEL}"
    instruction: |
      You are the Comprehension Goldfish (egm-comprehension). Load your egm-comprehension skill if needed.
      Audit the design draft as a fresh reader with zero prior context, flagging undefined schemas, missing idempotency headers, or ambiguous semantics.
      Return ONLY valid JSON with fields: reviewer ("goldfish-comprehension"), verdict ("NEEDS_WORK" or "APPROVED"),
      summary (1 sentence), and findings (array of 2 objects with severity, title, recommendation).
    config:
      maxOutputTokens: 2048
      temperature: 0.1
    maxTurns: 4
    output:
      format: json
      schema:
        reviewer: string
        verdict: string
        summary: string
        findings(array):
          severity: string
          title: string
          recommendation: string
    use:
      - name: genkit-middleware/skills
YAML

printf '==> [2/5] Applying 4 Workspaces and 4 Tasks (1 Elephant + 3 Goldfish)...\n'
ax apply -f "${TMP_MANIFEST}"

printf '\n==> [3/5] Provisioning Substrate actors and warming router mTLS cache...\n'
# Resume elephant-architect first and warm router mTLS cache; suspend Goldfish tasks after actor creation
ax resume task elephant-architect -a "${ATESPACE}"
ax ssh elephant-architect -a "${ATESPACE}" -- true
for gf in goldfish-design goldfish-catalyst goldfish-comprehension; do
  ax resume task "${gf}" -a "${ATESPACE}"
  ax suspend task "${gf}" -a "${ATESPACE}"
done
ax get tasks -a "${ATESPACE}"

printf '\n==> [4/5] Running egm-orchestrator (--mode=egm-panel)...\n'
(
  cd "${SCRIPT_DIR}"
  go run ./cmd/egm-orchestrator \
    --mode egm-panel \
    --atespace "${ATESPACE}" \
    --ax-namespace "${AX_SYSTEM_NAMESPACE:-ax-system}" \
    --context "${KUBE_CONTEXT:-kind-ax-e2e}" \
    --ax-bin "${AX_BIN}"
)

printf '\n==> [5/5] Inspecting final artifacts inside elephant-architect via `ax ssh`...\n'
ax get tasks -a "${ATESPACE}"

printf '\n--- [elephant-architect:/workspace/RESOLUTION_LOG.md] ---\n'
ax ssh elephant-architect -a "${ATESPACE}" -- cat /workspace/RESOLUTION_LOG.md

printf '\n--- [elephant-architect:/workspace/DESIGN_SPEC.md (head -n 35)] ---\n'
ax ssh elephant-architect -a "${ATESPACE}" -- head -n 35 /workspace/DESIGN_SPEC.md

printf '\n==> [Example 01] Sandboxed EGM Design & Review Loop completed!\n'
