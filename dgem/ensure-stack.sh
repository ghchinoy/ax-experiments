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

# ensure-stack.sh — Pre-flight verification, cold-start bootstrap, and teardown
# for the local dgem Metal stack (:8080 + :8095) + AX Apple container stack (:8090).
#
# Usage:
#   ./dgem/ensure-stack.sh up       # Ensure container runtime, diffgemma (:8080), dgem serve (:8095), ax-agent-local:latest, and ate-local (:8090) are running
#   ./dgem/ensure-stack.sh status   # Report status of both local stacks
#   ./dgem/ensure-stack.sh down     # Stop both local stacks cleanly
#   ./dgem/ensure-stack.sh image    # Build the shared dgem-genkit-task:latest image in /tmp

set -euo pipefail

DGEM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AX_EXP_ROOT="$(cd "${DGEM_DIR}/.." && pwd)"
DGEM_REPO="${DGEM_REPO:-$HOME/projects/dgem}"
DGEM_GATEWAY_PORT="${DGEM_GATEWAY_PORT:-8095}"
DGEM_GATEWAY_HOST="${DGEM_GATEWAY_HOST:-0.0.0.0}"
DGEM_BRIDGE_HOST="${DGEM_BRIDGE_HOST:-192.168.64.1}"
DGEM_ALLOWED_HOSTS="${DGEM_ALLOWED_HOSTS:-${DGEM_BRIDGE_HOST},host.docker.internal,host.containers.internal}"
DGEM_CTX="${DIFFGEMMA_CTX:-4096}"
DGEM_CLOUDRUN_URL="${DGEM_CLOUDRUN_URL:-}"
if [[ -n "${DGEM_CLOUDRUN_URL}" ]]; then
  DGEM_BACKEND="${DGEM_BACKEND:-cloudrun}"
else
  DGEM_BACKEND="${DGEM_BACKEND:-local}"
fi
DGEM_GATEWAY_URL="${DGEM_GATEWAY_URL:-http://${DGEM_BRIDGE_HOST}:${DGEM_GATEWAY_PORT}}"
DGEM_MCP_URL="${DGEM_MCP_URL:-${DGEM_GATEWAY_URL}/mcp}"

export DGEM_REPO DGEM_GATEWAY_PORT DGEM_GATEWAY_HOST DGEM_ALLOWED_HOSTS DGEM_CLOUDRUN_URL DGEM_BACKEND DGEM_GATEWAY_URL DGEM_MCP_URL

ensure_dgem_stack() {
  if [[ ! -d "${DGEM_REPO}" ]]; then
    echo "Error: DGEM_REPO not found at ${DGEM_REPO}." >&2
    echo "Clone https://github.com/GoogleCloudPlatform/dgem to ${DGEM_REPO} or set DGEM_REPO." >&2
    return 1
  fi

  # 1. Apple container runtime
  if ! command -v container >/dev/null 2>&1; then
    echo "Error: Apple 'container' CLI not found (/usr/local/bin/container)." >&2
    return 1
  fi
  if ! container list >/dev/null 2>&1; then
    echo "==> Starting Apple container system daemon..."
    container system start
  fi

  # 2. Upstream dgem inference backend: either remote Cloud Run GPU (when DGEM_CLOUDRUN_URL is set)
  #    or local Apple Silicon Metal diffgemma (:8080)
  if [[ -n "${DGEM_CLOUDRUN_URL}" ]]; then
    local cr_health_code
    cr_health_code="$(curl -s -m 3 -o /dev/null -w "%{http_code}" "${DGEM_CLOUDRUN_URL%/v1}/health" 2>/dev/null || echo "000")"
    if [[ "${cr_health_code}" == "404" ]]; then
      echo "==> Warning: DGEM_CLOUDRUN_URL (${DGEM_CLOUDRUN_URL}) returned HTTP 404 (service torn down); falling back to local Metal diffgemma (:8080)..."
      DGEM_CLOUDRUN_URL=""
      DGEM_BACKEND="local"
      export DGEM_CLOUDRUN_URL DGEM_BACKEND
    fi
  fi

  if [[ -n "${DGEM_CLOUDRUN_URL}" ]]; then
    echo "==> Using remote Cloud Run GPU upstream (${DGEM_CLOUDRUN_URL}, backend=${DGEM_BACKEND})..."
    if [[ -f "${DGEM_REPO}/diffgemma.pid" ]] || lsof -i :8080 >/dev/null 2>&1; then
      echo "==> Stopping local diffgemma (:8080) to free unified memory..."
      (cd "${DGEM_REPO}" && ./scripts/stop_server.sh) >/dev/null 2>&1 || true
    fi
  else
    if ! curl -fsSL -m 2 "http://127.0.0.1:8080/v1/models" >/dev/null 2>&1; then
      if [[ ! -f "${DGEM_REPO}/model/diffgemma-26b-a4b-it-q4/model.dgq.bin" ]] && [[ -d "$HOME/projects/diffusiongemma/model" ]]; then
        mkdir -p "${DGEM_REPO}/model"
        ln -sfn "$HOME/projects/diffusiongemma/model/diffgemma-26b-a4b-it-q4" "${DGEM_REPO}/model/diffgemma-26b-a4b-it-q4"
      fi
      echo "==> Starting local diffgemma Metal server (CTX=${DGEM_CTX})..."
      (cd "${DGEM_REPO}" && DIFFGEMMA_CTX="${DGEM_CTX}" ./scripts/serve.sh)
    fi
  fi

  # 3. dgem serve gateway (:8095 bound on 0.0.0.0 with DGEM_ALLOWED_HOSTS=192.168.64.1)
  if curl -fsSL -m 2 "http://127.0.0.1:${DGEM_GATEWAY_PORT}/health" >/dev/null 2>&1; then
    local running_backend
    running_backend="$(curl -fsSL -m 2 "http://127.0.0.1:${DGEM_GATEWAY_PORT}/api/backend-config" 2>/dev/null | jq -r '.default_backend // empty' || true)"
    if [[ -n "${running_backend}" && "${running_backend}" != "${DGEM_BACKEND}" ]]; then
      echo "==> Switching dgem serve gateway on :${DGEM_GATEWAY_PORT} from backend=${running_backend} to backend=${DGEM_BACKEND}..."
      (cd "${DGEM_REPO}" && DGEM_GATEWAY_PORT="${DGEM_GATEWAY_PORT}" ./scripts/stop_gateway.sh)
    fi
  fi

  if ! curl -fsSL -m 2 "http://127.0.0.1:${DGEM_GATEWAY_PORT}/health" >/dev/null 2>&1; then
    if [[ -n "${DGEM_CLOUDRUN_URL}" ]]; then
      if [[ -z "${DGEM_SERVER_KEY:-}" ]] && command -v gcloud >/dev/null 2>&1; then
        DGEM_SERVER_KEY="$(gcloud secrets versions access latest --secret="${SERVER_KEY_SECRET:-dgem-server-key}" 2>/dev/null || true)"
        export DGEM_SERVER_KEY
      fi
      echo "==> Starting dgem serve gateway on ${DGEM_GATEWAY_HOST}:${DGEM_GATEWAY_PORT} -> Cloud Run GPU (${DGEM_CLOUDRUN_URL})..."
      (
        cd "${DGEM_REPO}"
        if [[ ! -x "./bin/dgem" ]]; then
          go build -o "./bin/dgem" .
        fi
        nohup ./bin/dgem serve \
          -u "${DGEM_CLOUDRUN_URL}" \
          --gcp-auth \
          --default-backend "${DGEM_BACKEND}" \
          --host "${DGEM_GATEWAY_HOST}" \
          --port "${DGEM_GATEWAY_PORT}" \
          --allowed-hosts "${DGEM_ALLOWED_HOSTS}" \
          --templates-dir "./templates" > gateway.log 2>&1 &
        echo $! > dgem-gateway.pid
        for _ in $(seq 1 30); do
          if curl -fsSL -m 1 "http://127.0.0.1:${DGEM_GATEWAY_PORT}/health" >/dev/null 2>&1; then
            break
          fi
          sleep 0.5
        done
      )
    else
      echo "==> Starting dgem serve gateway on ${DGEM_GATEWAY_HOST}:${DGEM_GATEWAY_PORT} (allowed-hosts=${DGEM_ALLOWED_HOSTS})..."
      (
        cd "${DGEM_REPO}"
        DGEM_GATEWAY_PORT="${DGEM_GATEWAY_PORT}" \
        DGEM_GATEWAY_HOST="${DGEM_GATEWAY_HOST}" \
        DGEM_ALLOWED_HOSTS="${DGEM_ALLOWED_HOSTS}" \
        ./scripts/serve_gateway.sh
      )
    fi
  fi

  # 4. AX + ate-local control plane (:8090)
  source "${AX_EXP_ROOT}/swarm/lib.sh"
  if [[ ! -x "${AX_BIN}" ]] || ! "${AX_BIN}" get tasks >/dev/null 2>&1; then
    echo "==> Starting local AX + ate-local stack..."
    make -C "${AX_EXP_ROOT}" stack-up
  fi

  # 5. Base Apple container images (ax-agent-local:latest + ghcr.io/ghchinoy/ax-images/* when ~/projects/ax-images is present)
  if ! container image list 2>/dev/null | awk 'NR>1 {print $1":"$2}' | grep -qx "ax-agent-local:latest"; then
    echo "==> Building base image ax-agent-local:latest..."
    make -C "${AX_EXP_ROOT}" agent-image
  fi
  if [[ -d "${HOME}/projects/ax-images" ]] && ! container image list 2>/dev/null | awk 'NR>1 {print $1":"$2}' | grep -qx "ghcr.io/ghchinoy/ax-images/agy-agent:latest"; then
    echo "==> Building ghcr.io/ghchinoy/ax-images/* via ~/projects/ax-images..."
    make -C "${HOME}/projects/ax-images" apple-local
  fi
}

ensure_dgem_task_image() {
  local stage_dir
  mkdir -p "${HOME}/.cache/ax-experiments"
  stage_dir="$(mktemp -d "${HOME}/.cache/ax-experiments/dgem-task-image-XXXXXX")"
  trap 'rm -rf "${stage_dir}"' RETURN

  echo "==> Building shared linux/arm64 image dgem-genkit-task:latest..."
  mkdir -p "${stage_dir}/templates/calibration"

  GOOS=linux GOARCH=arm64 CGO_ENABLED=0 \
    go -C "${DGEM_REPO}/examples/genkit-tool-approval" build -trimpath -ldflags="-s -w" \
    -o "${stage_dir}/genkit-tool-approval" .
  GOOS=linux GOARCH=arm64 CGO_ENABLED=0 \
    go -C "${DGEM_REPO}/examples/genkit-bulk-synth" build -trimpath -ldflags="-s -w" \
    -o "${stage_dir}/genkit-bulk-synth" .
  GOOS=linux GOARCH=arm64 CGO_ENABLED=0 \
    go -C "${DGEM_DIR}/router" build -trimpath -ldflags="-s -w" \
    -o "${stage_dir}/dgem-router" .

  cp "${DGEM_REPO}"/templates/*.json.tmpl "${stage_dir}/templates/"
  cp "${DGEM_REPO}"/templates/calibration/*.json.tmpl "${stage_dir}/templates/calibration/"
  cp "${DGEM_DIR}/templates/specialist_router.json.tmpl" "${stage_dir}/templates/"
  mkdir -p "${stage_dir}/agy-safety-gate"
  cp "${DGEM_REPO}/examples/agy-safety-gate/dgem_gate.py" "${stage_dir}/agy-safety-gate/"
  cp "${DGEM_REPO}/examples/agy-safety-gate/sdk_demo.py" "${stage_dir}/agy-safety-gate/"

  cat > "${stage_dir}/Containerfile" <<'EOF'
FROM ax-agent-local:latest
COPY genkit-tool-approval /usr/local/bin/genkit-tool-approval
COPY genkit-bulk-synth /usr/local/bin/genkit-bulk-synth
COPY dgem-router /usr/local/bin/dgem-router
COPY agy-safety-gate /opt/dgem/agy-safety-gate
COPY templates /opt/dgem/templates
RUN chmod +x /usr/local/bin/genkit-tool-approval /usr/local/bin/genkit-bulk-synth /usr/local/bin/dgem-router /opt/dgem/agy-safety-gate/dgem_gate.py /opt/dgem/agy-safety-gate/sdk_demo.py
EOF

  container build -t dgem-genkit-task:latest -f "${stage_dir}/Containerfile" "${stage_dir}" >/dev/null
}

dgem_stack_status() {
  make -C "${DGEM_REPO}" DGEM_GATEWAY_PORT="${DGEM_GATEWAY_PORT}" local-status
  echo
  make -C "${AX_EXP_ROOT}" stack-status
}

dgem_stack_down() {
  echo "==> Stopping AX + ate-local stack..."
  make -C "${AX_EXP_ROOT}" stack-down || true
  echo "==> Stopping dgem gateway (:${DGEM_GATEWAY_PORT}) and diffgemma (:8080)..."
  (cd "${DGEM_REPO}" && DGEM_GATEWAY_PORT="${DGEM_GATEWAY_PORT}" make local-down) || true
}

dgem_cloudrun_down() {
  echo "==> Tearing down Cloud Run GPU service (dgemma)..."
  make -C "${DGEM_REPO}" cloudrun-teardown || true
  echo "==> Switching local dgem gateway (:${DGEM_GATEWAY_PORT}) back to local Metal diffgemma (:8080)..."
  DGEM_CLOUDRUN_URL=""
  DGEM_BACKEND="local"
  export DGEM_CLOUDRUN_URL DGEM_BACKEND
  ensure_dgem_stack
  dgem_stack_status
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  case "${1:-up}" in
    up)
      ensure_dgem_stack
      dgem_stack_status
      ;;
    status)
      dgem_stack_status
      ;;
    down)
      dgem_stack_down
      ;;
    cloudrun-down)
      dgem_cloudrun_down
      ;;
    image)
      ensure_dgem_stack
      ensure_dgem_task_image
      ;;
    *)
      echo "Usage: $0 {up|status|down|cloudrun-down|image}" >&2
      exit 1
      ;;
  esac
fi
