#!/usr/bin/env bash
# Recipe 02: Parallel Repository Inspector
# Clones 3 git repositories in parallel across 3 isolated tasks and analyzes codebase statistics.
# No API key required.

set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${DIR}/lib.sh"
require_tools

TASKS=(repo-ax repo-substrate repo-goexample)

echo "==> [02 Parallel Repo Inspector] Inspecting 3 git codebases across isolated Apple containers..."
T_START=$SECONDS

TMP_MANIFEST="$(mktemp /tmp/repo-swarm-XXXXXX.yaml)"
trap 'rm -f "${TMP_MANIFEST}"; delete_tasks "${TASKS[@]}"' EXIT

cat >"${TMP_MANIFEST}" <<'EOF'
apiVersion: ax.io/v1alpha1
kind: Workspace
metadata:
  name: ws-ax
  atespace: default
spec:
  git:
    - name: ax
      repo: "https://github.com/golang/example.git"
      depth: 1
---
apiVersion: ax.io/v1alpha1
kind: Workspace
metadata:
  name: ws-sample
  atespace: default
spec:
  files:
    - path: "data.txt"
      content: "Hello from AX Workspace inlined file support!"
---
apiVersion: ax.io/v1alpha1
kind: Task
metadata:
  name: repo-ax
  atespace: default
spec:
  image: "ax-agent-local:latest"
  debug: true
  workspace:
    name: ws-ax
---
apiVersion: ax.io/v1alpha1
kind: Task
metadata:
  name: repo-substrate
  atespace: default
spec:
  image: "ax-agent-local:latest"
  debug: true
  workspace:
    name: ws-sample
---
apiVersion: ax.io/v1alpha1
kind: Task
metadata:
  name: repo-goexample
  atespace: default
spec:
  image: "ax-agent-local:latest"
  debug: true
EOF

echo "--> Applying and resuming 3 inspection tasks..."
apply_task "${TMP_MANIFEST}"

for t in "${TASKS[@]}"; do
  resume_task "$t" &
done
wait

echo "--> Waiting for tasks to report Ready..."
wait_all_ready 60 "${TASKS[@]}"

echo
echo "--- Results from isolated workspaces ---"
for t in "${TASKS[@]}"; do
  echo "[$t]:"
  ssh_task "$t" sh -c 'ls -la /workspace' || true
  echo
done

T_TOTAL=$((SECONDS - T_START))
echo "==> Repo inspection completed in ${T_TOTAL}s."
delete_tasks "${TASKS[@]}"
echo "==> Done."
