#!/usr/bin/env bash
# Recipe 04: Specialized Code Review Panel
# 3 parallel AI agents in isolated sandboxes reviewing code from 3 different perspectives:
# Security Auditor, Go Readability Mentor, and Performance Engineer.
# Requires GEMINI_API_KEY.

set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${DIR}/lib.sh"
require_tools

if [[ -z "${GEMINI_API_KEY:-}" ]]; then
  echo "Error: GEMINI_API_KEY environment variable is required for this recipe." >&2
  exit 1
fi

ROLES=("security-reviewer" "readability-reviewer" "performance-reviewer")
TASKS=()
for r in "${ROLES[@]}"; do
  TASKS+=("panel-${r}")
done

SAMPLE_CODE='
func FetchUserData(id string) (*UserData, error) {
    var query = "SELECT * FROM users WHERE id = " + id
    rows, err := db.Query(query)
    if err != nil {
        return nil, fmt.Errorf("Database query failed.")
    }
    defer rows.Close()
    var u UserData
    for rows.Next() {
        _ = rows.Scan(&u.Name, &u.Email)
    }
    return &u, nil
}
'

echo "==> [04 Code Review Panel] Launching 3 specialized AI agents on Apple Container..."
T_START=$SECONDS
trace_start "04-review-panel" "multi-agent-panel" 3
trace_node_add "panel-security-reviewer" "security-auditor" "Security Auditor"
trace_node_add "panel-readability-reviewer" "readability-mentor" "Readability Mentor"
trace_node_add "panel-performance-reviewer" "performance-engineer" "Performance Engineer"

TMP_MANIFEST="$(mktemp /tmp/review-panel-XXXXXX.yaml)"
trap 'rm -f "${TMP_MANIFEST}"; delete_tasks "${TASKS[@]}"' EXIT

SAMPLE_CODE_INDENTED="$(printf '%s\n' "${SAMPLE_CODE}" | sed 's/^/        /')"

cat >"${TMP_MANIFEST}" <<EOF
apiVersion: ax.io/v1alpha1
kind: Task
metadata:
  name: panel-security-reviewer
  atespace: default
spec:
  image: "ax-agent-local:latest"
  debug: true
  env:
    - name: GEMINI_API_KEY
      value: "${GEMINI_API_KEY}"
    - name: AGENT_ROLE
      value: "Application Security Auditor"
    - name: AGENT_PROMPT
      value: |
        Analyze this Go code snippet strictly for security vulnerabilities, injection risks, and credential exposure. Give 2 concise bullet points:
${SAMPLE_CODE_INDENTED}
---
apiVersion: ax.io/v1alpha1
kind: Task
metadata:
  name: panel-readability-reviewer
  atespace: default
spec:
  image: "ax-agent-local:latest"
  debug: true
  env:
    - name: GEMINI_API_KEY
      value: "${GEMINI_API_KEY}"
    - name: AGENT_ROLE
      value: "Google Go Readability Mentor"
    - name: AGENT_PROMPT
      value: |
        Analyze this Go code snippet strictly for Go readability standards (error strings, naming, error handling). Give 2 concise bullet points:
${SAMPLE_CODE_INDENTED}
---
apiVersion: ax.io/v1alpha1
kind: Task
metadata:
  name: panel-performance-reviewer
  atespace: default
spec:
  image: "ax-agent-local:latest"
  debug: true
  env:
    - name: GEMINI_API_KEY
      value: "${GEMINI_API_KEY}"
    - name: AGENT_ROLE
      value: "Systems Performance Engineer"
    - name: AGENT_PROMPT
      value: |
        Analyze this Go code snippet strictly for efficiency, memory allocations, and connection leaks. Give 2 concise bullet points:
${SAMPLE_CODE_INDENTED}
EOF

echo "--> Applying and resuming 3 review agents..."
apply_task "${TMP_MANIFEST}"

for t in "${TASKS[@]}"; do
  resume_task "$t" &
done
wait

echo "--> Waiting for agent containers to report Ready..."
wait_all_ready 60 "${TASKS[@]}"

echo "--> Executing AI review agents in parallel inside sandboxes..."
for t in "${TASKS[@]}"; do
  echo "============================================================"
  echo "Agent: ${t}"
  echo "============================================================"
  trace_msg "host" "$t" "dispatch code snippet" "${#SAMPLE_CODE}"
  rev="$(ssh_task "$t" python3 /usr/local/bin/agent.py || true)"
  trace_msg "$t" "host" "review output" "${#rev}"
  printf '%s\n' "${rev}"
  echo
done

T_TOTAL=$((SECONDS - T_START))
trace_end "04-review-panel" "success" "${T_TOTAL}"
echo "==> Multi-agent review panel completed in ${T_TOTAL}s."
delete_tasks "${TASKS[@]}"
echo "==> Done."
