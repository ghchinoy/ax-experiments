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

# Idempotent setup script for running AX + Agent Substrate (v1.0.0-rc.1+)
# locally on a Chromebook Linux (Crostini / Bagels KVM) VM running Debian 13
# (trixie).
#
# Usage:
#   ./crostini/setup-crostini.sh
#
# Configurable environment variables:
#   AX_REPO                    Path to google/ax checkout (default: ~/projects/ax)
#   AX_WORKER_REPLICAS         Number of gVisor worker replicas (default: 2 for 14 GiB RAM)
#   SUBSTRATE_IMAGE_CACHE_DIR  Persistent host cache for Substrate registry images
#                              (default: ~/.cache/substrate-registry)
#   PRUNE_DOCKER_BUILD_CACHE   Prune multi-stage Rust/Envoy build cache after setup (default: true)

set -euo pipefail

AX_REPO="${AX_REPO:-${HOME}/projects/ax}"
export AX_WORKER_REPLICAS="${AX_WORKER_REPLICAS:-2}"
export SUBSTRATE_IMAGE_CACHE_DIR="${SUBSTRATE_IMAGE_CACHE_DIR:-${HOME}/.cache/substrate-registry}"
PRUNE_DOCKER_BUILD_CACHE="${PRUNE_DOCKER_BUILD_CACHE:-true}"
KIND_VERSION="${KIND_VERSION:-v0.27.0}"

log() {
  printf '\n==> [crostini] %s\n' "$*" >&2
}

log "1/5 Running Chromebook / Crostini pre-flight checks..."
VIRT_VM="$(systemd-detect-virt -v || true)"
VIRT_CT="$(systemd-detect-virt -c || true)"
CGROUP_FS="$(stat -fc %T /sys/fs/cgroup)"
printf '  VM virtualization : %s\n' "${VIRT_VM}"
printf '  Container nesting : %s\n' "${VIRT_CT}"
printf '  Cgroup filesystem : %s\n' "${CGROUP_FS}"

if [[ "${CGROUP_FS}" != "cgroup2fs" ]]; then
  echo "error: expected cgroup2fs on /sys/fs/cgroup, got '${CGROUP_FS}'" >&2
  exit 1
fi

if [[ ! -d "${AX_REPO}/.git" ]]; then
  echo "error: AX_REPO (${AX_REPO}) does not exist or is not a git repository" >&2
  exit 1
fi

log "2/5 Installing Debian 13 (trixie) packages (docker.io, docker-cli, docker-buildx, gettext-base)..."
# Note: On Debian 13 (trixie), /usr/bin/docker is packaged in `docker-cli` (a
# Recommended package of `docker.io`), so both must be listed explicitly when
# using --no-install-recommends.
if ! command -v docker >/dev/null 2>&1 || ! command -v envsubst >/dev/null 2>&1; then
  sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    docker-buildx \
    docker-cli \
    docker.io \
    gettext-base \
    jq \
    openssl
fi

sudo systemctl enable --now docker
sudo usermod -aG docker "${USER}"
# Grant current shell immediate access to /var/run/docker.sock without requiring
# a full Crostini terminal restart.
if [[ ! -w /var/run/docker.sock ]]; then
  sudo setfacl -m "u:${USER}:rw" /var/run/docker.sock 2>/dev/null || sudo chmod 666 /var/run/docker.sock
fi

ARCH="$(dpkg --print-architecture)"

log "3/5 Ensuring kubectl and kind (${KIND_VERSION}, ${ARCH}) are installed..."
if ! command -v kubectl >/dev/null 2>&1; then
  K8S_VER="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
  sudo curl -fsSL "https://dl.k8s.io/release/${K8S_VER}/bin/linux/${ARCH}/kubectl" -o /usr/local/bin/kubectl
  sudo chmod +x /usr/local/bin/kubectl
fi

if ! command -v kind >/dev/null 2>&1; then
  sudo curl -fsSL "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-${ARCH}" -o /usr/local/bin/kind
  sudo chmod +x /usr/local/bin/kind
fi

docker info --format '  Docker={{.ServerVersion}} StorageDriver={{.Driver}} CgroupDriver={{.CgroupDriver}}v{{.CgroupVersion}}'
printf '  kubectl=%s\n' "$(kubectl version --client -o yaml | awk '/gitVersion:/ {print $2; exit}')"
printf '  kind=%s\n' "$(kind --version)"

log "4/5 Provisioning Kind + Agent Substrate + AX (AX_WORKER_REPLICAS=${AX_WORKER_REPLICAS})..."
mkdir -p "${SUBSTRATE_IMAGE_CACHE_DIR}"
(
  cd "${AX_REPO}"
  ./hack/setup-e2e-kind.sh
)

if [[ "${PRUNE_DOCKER_BUILD_CACHE}" == "true" ]]; then
  log "5/5 Pruning intermediate Docker build cache to save Crostini rootfs space..."
  docker builder prune -f >/dev/null 2>&1 || true
fi

log "Crostini AX + Agent Substrate environment is ready!"
cat <<EOF

To use the cluster in your current shell:

  source "${AX_REPO}/.tmp/e2e.env"
  export PATH="\$(dirname "\$AX_BIN"):\$PATH"

  kubectl get pods -A
  cd "${AX_REPO}" && ./demo.sh
EOF
