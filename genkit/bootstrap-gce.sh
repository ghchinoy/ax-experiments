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

# GCE Ubuntu 24.04 LTS startup script that provisions Docker, Kind, kubectl,
# Go 1.27+, Agent Substrate (v0.6.0), AX, and the genkit-runner image.
#
# Usage with gcloud:
#   gcloud compute instances create ax-genkit-e2e \
#     --machine-type=n2-standard-8 \
#     --image-family=ubuntu-2404-lts-amd64 \
#     --image-project=ubuntu-os-cloud \
#     --boot-disk-size=100GB \
#     --boot-disk-type=pd-balanced \
#     --scopes=cloud-platform \
#     --metadata-from-file=startup-script=genkit/bootstrap-gce.sh
#
# To bake a reusable GCE custom image after first boot completes:
#   gcloud compute images create ax-substrate-v0-6-0-ubuntu2404 \
#     --source-disk=ax-genkit-e2e --source-disk-zone=<zone>

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
LOG_FILE="/var/log/ax-genkit-bootstrap.log"
exec > >(tee -a "${LOG_FILE}") 2>&1

echo "==> [1/6] Installing OS packages (docker, git, make, jq, openssl, gettext-base)..."
apt-get update -qq
apt-get install -y -qq \
  ca-certificates \
  curl \
  docker.io \
  gettext-base \
  git \
  jq \
  make \
  openssl
systemctl enable --now docker

ARCH="$(dpkg --print-architecture)"

echo "==> [2/6] Installing Go, kubectl, and kind (${ARCH})..."
if ! command -v go >/dev/null 2>&1; then
  GO_TARBALL="go1.24.2.linux-${ARCH}.tar.gz"
  curl -fsSL "https://go.dev/dl/${GO_TARBALL}" -o "/tmp/${GO_TARBALL}"
  rm -rf /usr/local/go && tar -C /usr/local -xzf "/tmp/${GO_TARBALL}"
  rm -f "/tmp/${GO_TARBALL}"
fi
export PATH="/usr/local/go/bin:/root/go/bin:/usr/local/bin:${PATH}"
export GOTOOLCHAIN=auto

if ! command -v kubectl >/dev/null 2>&1; then
  K8S_VER="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
  curl -fsSL "https://dl.k8s.io/release/${K8S_VER}/bin/linux/${ARCH}/kubectl" -o /usr/local/bin/kubectl
  chmod +x /usr/local/bin/kubectl
fi

if ! command -v kind >/dev/null 2>&1; then
  curl -fsSL "https://kind.sigs.k8s.io/dl/v0.27.0/kind-linux-${ARCH}" -o /usr/local/bin/kind
  chmod +x /usr/local/bin/kind
fi

echo "==> [3/6] Cloning ghchinoy/ax (feat/genkit-runner) and ghchinoy/ax-experiments..."
mkdir -p /opt
if [[ ! -d /opt/ax/.git ]]; then
  git clone -b feat/genkit-runner https://github.com/ghchinoy/ax.git /opt/ax
fi
if [[ ! -d /opt/ax-experiments/.git ]]; then
  git clone https://github.com/ghchinoy/ax-experiments.git /opt/ax-experiments
fi

echo "==> [4/6] Provisioning Kind + Agent Substrate + AX via make e2e-setup..."
# Store Substrate images in /var/cache/substrate-registry so baking a GCE custom
# image from this disk lets subsequent boots skip building Substrate from source.
export SUBSTRATE_IMAGE_CACHE_DIR="/var/cache/substrate-registry"
mkdir -p "${SUBSTRATE_IMAGE_CACHE_DIR}"

cd /opt/ax
make e2e-setup

echo "==> [5/6] Building and pushing genkit-runner to localhost:5001..."
make push-genkit-image \
  CONTAINER_CLI=docker \
  GENKIT_REPO=localhost:5001/genkit-runner \
  GENKIT_BASE_IMAGE=localhost:5001/ax-task-runner:base

echo "==> [6/6] Writing /etc/profile.d/ax-e2e.sh for interactive shells..."
cat >/etc/profile.d/ax-e2e.sh <<'EOF'
export PATH="/opt/ax/.tmp/bin:/usr/local/go/bin:${PATH}"
if [[ -f /opt/ax/.tmp/e2e.env ]]; then
  source /opt/ax/.tmp/e2e.env
fi
EOF

echo "==> Bootstrap complete! Genkit image digest: localhost:5001/genkit-runner@$(cat /opt/ax/bin/genkit-runner.digest)"
