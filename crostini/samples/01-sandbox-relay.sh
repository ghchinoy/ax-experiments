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

# Sample 1: Two-Task gVisor Sandbox Handoff & RustFS Checkpoint Pipeline
#
# Demonstrates two isolated AX tasks (repo-scanner -> release-builder)
# sharing a structured JSON artifact across distinct gVisor sandboxes on a
# Chromebook Crostini Kind + Agent Substrate cluster, without requiring any
# external LLM API key.
#
# Lifecycle:
#   1. Apply two Workspaces and two Tasks (repo-scanner, release-builder).
#   2. Resume repo-scanner: clones /opt/ax-e2e-sample-repo.git into /workspace/repo,
#      analyzes commits/tags/hashes, emits /workspace/handoff.json, and suspends.
#   3. Relay handoff.json into release-builder: verifies repository state in a
#      second gVisor sandbox, generates /workspace/RELEASE_NOTES.md, suspends to
#      RustFS, resumes, and proves /workspace/RELEASE_NOTES.md persisted.

set -euo pipefail

AX_REPO="${AX_REPO:-${HOME}/projects/ax}"
if [[ -f "${AX_REPO}/.tmp/e2e.env" ]]; then
  # shellcheck disable=SC1090
  source "${AX_REPO}/.tmp/e2e.env"
fi
AX_BIN="${AX_BIN:-${AX_REPO}/.tmp/bin/ax}"
ATESPACE="${ATESPACE:-default}"

ax() { "${AX_BIN}" "$@"; }

TMP_MANIFEST="$(mktemp /tmp/ax-sample01-XXXXXX.yaml)"
cleanup() {
  rm -f "${TMP_MANIFEST}"
  ax delete task repo-scanner -a "${ATESPACE}" >/dev/null 2>&1 || true
  ax delete task release-builder -a "${ATESPACE}" >/dev/null 2>&1 || true
  ax delete workspace scanner-ws -a "${ATESPACE}" >/dev/null 2>&1 || true
  ax delete workspace builder-ws -a "${ATESPACE}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

printf '\n==> [Sample 01] Cleaning up any prior sample resources...\n'
cleanup
TMP_MANIFEST="$(mktemp /tmp/ax-sample01-XXXXXX.yaml)"

cat <<'YAML' > "${TMP_MANIFEST}"
apiVersion: ax.io/v1alpha1
kind: Workspace
metadata:
  name: scanner-ws
  atespace: default
spec:
  git:
    - repo: file:///opt/ax-e2e-sample-repo.git
      branch: main
      dir: repo
  files:
    - path: "scan_repo.py"
      content: |
        import hashlib, json, os, platform, subprocess

        repo_dir = "/workspace/repo"
        commit = subprocess.check_output(["git", "-C", repo_dir, "rev-parse", "--short", "HEAD"], text=True).strip()
        tags = subprocess.check_output(["git", "-C", repo_dir, "tag", "--list"], text=True).split()
        log_lines = subprocess.check_output(["git", "-C", repo_dir, "log", "--oneline"], text=True).strip().splitlines()

        files = {}
        for name in sorted(os.listdir(repo_dir)):
            p = os.path.join(repo_dir, name)
            if os.path.isfile(p):
                with open(p, "rb") as f:
                    files[name] = hashlib.sha256(f.read()).hexdigest()[:16]

        artifact = {
            "producer_task": "repo-scanner",
            "producer_kernel": platform.release(),
            "head_commit": commit,
            "tags": tags,
            "commits": log_lines,
            "file_sha256_prefix": files,
        }
        with open("/workspace/handoff.json", "w") as out:
            json.dump(artifact, out, indent=2)
        print(json.dumps(artifact, indent=2))
---
apiVersion: ax.io/v1alpha1
kind: Workspace
metadata:
  name: builder-ws
  atespace: default
spec:
  git:
    - repo: file:///opt/ax-e2e-sample-repo.git
      branch: main
      dir: repo
  files:
    - path: "build_release.py"
      content: |
        import hashlib, json, os, platform

        with open("/workspace/handoff.json") as f:
            handoff = json.load(f)

        repo_dir = "/workspace/repo"
        verified = []
        for fname, expected_hash in handoff["file_sha256_prefix"].items():
            with open(os.path.join(repo_dir, fname), "rb") as rf:
                actual_hash = hashlib.sha256(rf.read()).hexdigest()[:16]
            assert actual_hash == expected_hash, f"mismatch for {fname}: {actual_hash} != {expected_hash}"
            verified.append(f"- `{fname}`: sha256 prefix `{actual_hash}` (verified)")

        notes = [
            f"# Release Notes (HEAD `{handoff['head_commit']}`)",
            "",
            f"- **Scanned by**: `{handoff['producer_task']}` (`{handoff['producer_kernel']}`)",
            f"- **Verified by**: `release-builder` (`{platform.release()}`)",
            f"- **Tags**: {', '.join(handoff['tags'])}",
            "",
            "## Commit Log",
            *[f"- {c}" for c in handoff["commits"]],
            "",
            "## Verified Artifacts",
            *verified,
            "",
        ]
        report = "\n".join(notes)
        with open("/workspace/RELEASE_NOTES.md", "w") as out:
            out.write(report)
        print(report)
---
apiVersion: ax.io/v1alpha1
kind: Task
metadata:
  name: repo-scanner
  atespace: default
spec:
  debug: true
  workspace:
    name: scanner-ws
---
apiVersion: ax.io/v1alpha1
kind: Task
metadata:
  name: release-builder
  atespace: default
spec:
  debug: true
  workspace:
    name: builder-ws
YAML

printf '==> [1/5] Applying Workspaces (scanner-ws, builder-ws) and Tasks (repo-scanner, release-builder)...\n'
ax apply -f "${TMP_MANIFEST}"

printf '\n==> [2/5] Resuming Task 1 (repo-scanner) and generating /workspace/handoff.json...\n'
ax resume task repo-scanner -a "${ATESPACE}"
SCANNER_IP="$(ax get task repo-scanner -a "${ATESPACE}" | awk '/workerIP:/ {print $2}')"
printf '    repo-scanner running on gVisor worker IP: %s\n' "${SCANNER_IP}"

HANDOFF_JSON="$(ax ssh repo-scanner -a "${ATESPACE}" -- python3 /workspace/scan_repo.py)"
printf '%s\n' "${HANDOFF_JSON}"

printf '\n==> [3/5] Suspending Task 1 (repo-scanner) to release its worker and checkpoint /workspace to RustFS...\n'
ax suspend task repo-scanner -a "${ATESPACE}"
ax get tasks -a "${ATESPACE}"

printf '\n==> [4/5] Resuming Task 2 (release-builder) and relaying handoff.json...\n'
ax resume task release-builder -a "${ATESPACE}"
BUILDER_IP="$(ax get task release-builder -a "${ATESPACE}" | awk '/workerIP:/ {print $2}')"
printf '    release-builder running on gVisor worker IP: %s\n' "${BUILDER_IP}"

HANDOFF_B64="$(printf '%s' "${HANDOFF_JSON}" | base64 -w0)"
ax ssh release-builder -a "${ATESPACE}" -- sh -c "echo '${HANDOFF_B64}' | base64 -d > /workspace/handoff.json && python3 /workspace/build_release.py"

printf '\n==> [5/5] Suspending and resuming Task 2 (release-builder) to verify RustFS snapshot persistence...\n'
ax suspend task release-builder -a "${ATESPACE}"
ax resume task release-builder -a "${ATESPACE}"
printf '%s\n' '--- Persisted /workspace/RELEASE_NOTES.md after resume ---'
ax ssh release-builder -a "${ATESPACE}" -- cat /workspace/RELEASE_NOTES.md
printf '%s\n' '----------------------------------------------------------'
printf '==> [Sample 01] Completed successfully!\n'
