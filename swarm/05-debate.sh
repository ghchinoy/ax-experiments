#!/usr/bin/env bash
# Recipe 05: Agent Debate & Red-Team Round
# Two AI agents in separate isolated containers engage in a structured debate.
# The host orchestrator streams the proposer's output into the critic's container.
# Requires GEMINI_API_KEY.

set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${DIR}/lib.sh"
require_tools

if [[ -z "${GEMINI_API_KEY:-}" ]]; then
  echo "Error: GEMINI_API_KEY environment variable is required for this recipe." >&2
  exit 1
fi

TASKS=(debate-proposer debate-critic)

echo "==> [05 Agent Debate] Launching Proposer and Critic in isolated microVMs..."
T_START=$SECONDS
trace_start "05-debate" "adversarial-debate" 2
trace_node_add "debate-proposer" "proposer" "Proposer"
trace_node_add "debate-critic" "critic" "Critic"

TMP_MANIFEST="$(mktemp /tmp/debate-XXXXXX.yaml)"
trap 'rm -f "${TMP_MANIFEST}"; delete_tasks "${TASKS[@]}"' EXIT

cat >"${TMP_MANIFEST}" <<EOF
apiVersion: ax.io/v1alpha1
kind: Task
metadata:
  name: debate-proposer
  atespace: default
spec:
  image: "ax-agent-local:latest"
  debug: true
  env:
    - name: GEMINI_API_KEY
      value: "${GEMINI_API_KEY}"
    - name: AGENT_ROLE
      value: "Radical Performance Advocate"
    - name: AGENT_PROMPT
      value: "Argue in exactly 2 sentences why all database transactions should bypass disk and run purely in in-memory RAM."
---
apiVersion: ax.io/v1alpha1
kind: Task
metadata:
  name: debate-critic
  atespace: default
spec:
  image: "ax-agent-local:latest"
  debug: true
  env:
    - name: GEMINI_API_KEY
      value: "${GEMINI_API_KEY}"
    - name: AGENT_ROLE
      value: "Pragmatic Site Reliability Engineer"
EOF

echo "--> Applying and resuming debate agents..."
apply_task "${TMP_MANIFEST}"

for t in "${TASKS[@]}"; do
  resume_task "$t" &
done
wait

echo "--> Waiting for debate agents to report Ready..."
wait_all_ready 60 "${TASKS[@]}"

echo
trace_note "Round 1: Proposer Opening Argument"
trace_msg "host" "debate-proposer" "request opening argument" 120
echo "--- Round 1: Proposer's Opening Argument ---"
PROPOSAL="$(ssh_task debate-proposer python3 /usr/local/bin/agent.py)"
trace_msg "debate-proposer" "host" "proposer opening statement" "${#PROPOSAL}"
echo "${PROPOSAL}"
echo

trace_note "Round 2: Critic Rebuttal"
trace_msg "host" "debate-critic" "stream proposal for rebuttal" "${#PROPOSAL}"
echo "--- Round 2: Critic's Rebuttal (streaming argument into Critic container) ---"
REBUTTAL="$(ssh_task debate-critic sh -c "AGENT_PROMPT='Rebut this proposal in exactly 2 sentences highlighting durability, power loss, and disaster recovery: \"$PROPOSAL\"' python3 /usr/local/bin/agent.py")"
trace_msg "debate-critic" "host" "critic rebuttal argument" "${#REBUTTAL}"
echo "${REBUTTAL}"
echo

T_TOTAL=$((SECONDS - T_START))
trace_end "05-debate" "success" "${T_TOTAL}"
echo "==> Multi-agent debate completed in ${T_TOTAL}s."
delete_tasks "${TASKS[@]}"
echo "==> Done."
