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

# Common library for AX Swarm recipes on Apple Container.

AX_REPO="${AX_REPO:-$HOME/projects/ax}"
AX_BIN="${AX_BIN:-${AX_REPO}/.ax-local/bin/ax}"
if [[ ! -x "${AX_BIN}" ]]; then
  AX_BIN="${AX_REPO}/bin/ax"
fi

AX_SERVER="${AX_SERVER:-localhost:8090}"
export AX_SERVER

trace_event() {
  if [[ -n "${AX_TRACE_RECIPE:-}" ]]; then
    local now
    now="$(python3 -c 'import time; print(f"{time.time():.3f}")' 2>/dev/null || date +%s)"
    printf '{"t":%s,"src":"recipe",%s}\n' "${now}" "$1" >> "${AX_TRACE_RECIPE}"
  fi
}

trace_start() {
  local name="$1" pattern="$2" count="$3"
  trace_event "\"kind\":\"run.start\",\"id\":\"${name}\",\"label\":\"${name}\",\"meta\":{\"pattern\":\"${pattern}\",\"tasks\":${count}}"
}

trace_end() {
  local name="$1" status="$2" duration="$3"
  trace_event "\"kind\":\"run.end\",\"id\":\"${name}\",\"label\":\"${name}\",\"meta\":{\"status\":\"${status}\",\"duration\":${duration}}"
}

trace_node_add() {
  local name="$1" role="${2:-worker}" label="${3:-$1}"
  trace_event "\"kind\":\"node.add\",\"id\":\"${name}\",\"from\":\"host\",\"to\":\"${name}\",\"role\":\"${role}\",\"label\":\"${label}\""
}

trace_msg() {
  local from="$1" to="$2" label="$3" len="${4:-0}"
  trace_event "\"kind\":\"edge.msg\",\"from\":\"${from}\",\"to\":\"${to}\",\"label\":\"${label}\",\"meta\":{\"bytes\":${len}}"
}

trace_note() {
  local text="$1"
  trace_event "\"kind\":\"note\",\"label\":\"${text}\""
}

require_tools() {
  command -v container >/dev/null 2>&1 || { echo "Error: Apple 'container' CLI not found" >&2; exit 1; }
  [[ -x "${AX_BIN}" ]] || { echo "Error: ax binary not found at ${AX_BIN}. Run 'make local-up' first." >&2; exit 1; }
}

apply_task() {
  local yaml_file="$1"
  "${AX_BIN}" apply -f "${yaml_file}" >/dev/null
}

resume_task() {
  local task_name="$1"
  "${AX_BIN}" resume "${task_name}" >/dev/null
}

wait_ready() {
  local task_name="$1"
  local max_wait="${2:-45}"
  local start=$SECONDS

  while (( SECONDS - start < max_wait )); do
    local desc
    desc="$("${AX_BIN}" describe task "${task_name}" 2>/dev/null || true)"
    local phase
    phase="$(echo "${desc}" | awk '/Phase:/{print $2}')"
    local has_ready
    has_ready="$(echo "${desc}" | grep -E "Ready\s+True" || true)"
    local ip
    ip="$(echo "${desc}" | awk '/Worker IP:/{print $3}')"

    if [[ "${phase}" == "Running" && -n "${has_ready}" && -n "${ip}" && "${ip}" != "<none>" ]]; then
      return 0
    fi
    sleep 0.1
  done
  echo "Timed out waiting for task ${task_name} to be Ready" >&2
  return 1
}

wait_all_ready() {
  local max_wait="${1:-60}"
  shift
  local tasks=("$@")
  local start=$SECONDS

  for t in "${tasks[@]}"; do
    local remaining=$(( max_wait - (SECONDS - start) ))
    if (( remaining <= 0 )); then
      echo "Timed out waiting for swarm tasks" >&2
      return 1
    fi
    wait_ready "$t" "${remaining}" || return 1
  done
}

ssh_task() {
  local task_name="$1"
  shift
  local cmd_str="$*"
  trace_event "\"kind\":\"edge.exec\",\"from\":\"host\",\"to\":\"${task_name}\",\"label\":\"exec ${cmd_str:0:40}\",\"meta\":{\"state\":\"start\"}"
  local t0=$SECONDS
  local out
  local code=0
  out="$("${AX_BIN}" ssh "${task_name}" -- "$@")" || code=$?
  local elapsed=$(( SECONDS - t0 ))
  trace_event "\"kind\":\"edge.exec\",\"from\":\"host\",\"to\":\"${task_name}\",\"label\":\"exec done (${elapsed}s)\",\"meta\":{\"state\":\"end\",\"exitCode\":${code},\"duration\":${elapsed}}"
  printf '%s\n' "${out}"
  return $code
}

delete_tasks() {
  for t in "$@"; do
    "${AX_BIN}" delete task "$t" >/dev/null 2>&1 || true
  done
}

count_apple_containers() {
  container list 2>/dev/null | awk 'NR>1 {count++} END {print count+0}'
}
