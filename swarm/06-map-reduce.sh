#!/usr/bin/env bash
# Recipe 06: Map-Reduce Agent Swarm
# 3 Mapper agents analyze different concepts in parallel; 1 Reducer agent synthesizes the results.
# Requires GEMINI_API_KEY.

set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${DIR}/lib.sh"
require_tools

if [[ -z "${GEMINI_API_KEY:-}" ]]; then
  echo "Error: GEMINI_API_KEY environment variable is required for this recipe." >&2
  exit 1
fi

MAPPERS=(map-topic-1 map-topic-2 map-topic-3)
ALL_TASKS=("${MAPPERS[@]}" reduce-synthesis)

echo "==> [06 Map-Reduce Swarm] Spawning 3 Mapper agents + 1 Reducer agent on Apple Container..."
T_START=$SECONDS
trace_start "06-map-reduce" "scatter-gather" 4
trace_node_add "map-topic-1" "mapper" "Mapper 1 (Kernel)"
trace_node_add "map-topic-2" "mapper" "Mapper 2 (Streams)"
trace_node_add "map-topic-3" "mapper" "Mapper 3 (Network)"
trace_node_add "reduce-synthesis" "reducer" "Reducer (Editor)"

TMP_MANIFEST="$(mktemp /tmp/mapreduce-XXXXXX.yaml)"
trap 'rm -f "${TMP_MANIFEST}"; delete_tasks "${ALL_TASKS[@]}"' EXIT

cat >"${TMP_MANIFEST}" <<EOF
apiVersion: ax.io/v1alpha1
kind: Task
metadata:
  name: map-topic-1
  atespace: default
spec:
  image: "ax-agent-local:latest"
  debug: true
  env:
    - name: GEMINI_API_KEY
      value: "${GEMINI_API_KEY}"
    - name: AGENT_ROLE
      value: "Kernel Architecture Analyst"
    - name: AGENT_PROMPT
      value: "Summarize in 1 concise sentence the key advantage of microVMs over standard Linux containers."
---
apiVersion: ax.io/v1alpha1
kind: Task
metadata:
  name: map-topic-2
  atespace: default
spec:
  image: "ax-agent-local:latest"
  debug: true
  env:
    - name: GEMINI_API_KEY
      value: "${GEMINI_API_KEY}"
    - name: AGENT_ROLE
      value: "Distributed Systems Analyst"
    - name: AGENT_PROMPT
      value: "Summarize in 1 concise sentence why distributed event streams (like Redis Streams or Kafka) decouple workers."
---
apiVersion: ax.io/v1alpha1
kind: Task
metadata:
  name: map-topic-3
  atespace: default
spec:
  image: "ax-agent-local:latest"
  debug: true
  env:
    - name: GEMINI_API_KEY
      value: "${GEMINI_API_KEY}"
    - name: AGENT_ROLE
      value: "Networking Analyst"
    - name: AGENT_PROMPT
      value: "Summarize in 1 concise sentence why direct bridge network routing reduces latency compared to proxy sidecars."
---
apiVersion: ax.io/v1alpha1
kind: Task
metadata:
  name: reduce-synthesis
  atespace: default
spec:
  image: "ax-agent-local:latest"
  debug: true
  env:
    - name: GEMINI_API_KEY
      value: "${GEMINI_API_KEY}"
    - name: AGENT_ROLE
      value: "Executive Editor"
EOF

echo "--> Applying and resuming all 4 tasks..."
apply_task "${TMP_MANIFEST}"

for t in "${ALL_TASKS[@]}"; do
  resume_task "$t" &
done
wait

echo "--> Waiting for all 4 agents to report Ready..."
wait_all_ready 60 "${ALL_TASKS[@]}"

echo "--> Executing 3 Mappers in parallel..."
trace_note "Scatter Phase: 3 Mappers in Parallel"
trace_msg "host" "map-topic-1" "map subtask: kernel" 100
trace_msg "host" "map-topic-2" "map subtask: streams" 120
trace_msg "host" "map-topic-3" "map subtask: network" 110

MAP_OUT_1="$(ssh_task map-topic-1 python3 /usr/local/bin/agent.py)"
trace_msg "map-topic-1" "host" "map result 1" "${#MAP_OUT_1}"

MAP_OUT_2="$(ssh_task map-topic-2 python3 /usr/local/bin/agent.py)"
trace_msg "map-topic-2" "host" "map result 2" "${#MAP_OUT_2}"

MAP_OUT_3="$(ssh_task map-topic-3 python3 /usr/local/bin/agent.py)"
trace_msg "map-topic-3" "host" "map result 3" "${#MAP_OUT_3}"

echo "   [Mapper 1]: ${MAP_OUT_1}"
echo "   [Mapper 2]: ${MAP_OUT_2}"
echo "   [Mapper 3]: ${MAP_OUT_3}"
echo

echo "--> Streaming combined mapper outputs to Reducer..."
trace_note "Gather Phase: Synthesis by Reducer"
COMBINED="Point 1: ${MAP_OUT_1}\nPoint 2: ${MAP_OUT_2}\nPoint 3: ${MAP_OUT_3}"
trace_msg "host" "reduce-synthesis" "stream aggregated map outputs" "${#COMBINED}"

REDUCED="$(ssh_task reduce-synthesis sh -c "AGENT_PROMPT='Synthesize these three technical findings into a single cohesive takeaway paragraph:\n${COMBINED}' python3 /usr/local/bin/agent.py")"
trace_msg "reduce-synthesis" "host" "final synthesis output" "${#REDUCED}"

echo "============================================================"
echo "SYNTHESIZED REDUCE RESULT"
echo "============================================================"
echo "${REDUCED}"

T_TOTAL=$((SECONDS - T_START))
trace_end "06-map-reduce" "success" "${T_TOTAL}"
echo
echo "==> Map-Reduce swarm completed in ${T_TOTAL}s."
delete_tasks "${ALL_TASKS[@]}"
echo "==> Done."
