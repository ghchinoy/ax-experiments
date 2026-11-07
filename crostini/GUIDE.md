# Running AX & Agent Substrate Locally on a Chromebook (Crostini VM)

> **OKF v0.2 Track Metadata & Lineage**: [`okf/crostini.md`](../okf/crostini.md) · **Track Overview**: [`crostini/README.md`](./README.md)

This guide walks through auditing a ChromeOS Linux (Crostini / Bagels) VM, installing the container and Kubernetes toolchain on Debian 13 (`trixie`), provisioning **Agent Substrate** (`v1.0.0-rc.1`) + **AX** on a local **Kind** cluster, and running sandboxed gVisor agent tasks (`Task`, `Workspace`, `Model`) end-to-end.

All steps, timings, and troubleshooting notes below were empirically verified on a 12th Gen Intel Core i5-1245U Chromebook (`14 GiB` RAM, `58 GiB` `btrfs` rootfs).

---

## 1. Pre-Flight Environment Audit

Modern ChromeOS runs the `penguin` Debian environment directly inside a KVM virtual machine ("Bagels") rather than an unprivileged LXC container nested inside Termina. Before installing Docker or Kind, verify your Crostini VM meets the kernel, virtualization, and storage requirements:

```bash
uname -a
systemd-detect-virt -v      # Expected: kvm
systemd-detect-virt -c      # Expected: none (not nested inside unprivileged LXC)
cat /proc/self/uid_map      # Expected: 0 0 4294967295 (full root UID range)
stat -fc %T /sys/fs/cgroup  # Expected: cgroup2fs
free -h && df -h /
ls -la /dev/kvm /dev/net/tun /dev/fuse
```

### Verified Chromebook Baseline (`penguin`)

| Component | Observed Value | Requirement / Notes |
|---|---|---|
| **OS** | Debian GNU/Linux 13 (`trixie`) `x86_64` | Ships Docker `26.1.5+dfsg1` in `apt` (`docker.io` + `docker-cli` + `docker-buildx`) |
| **Kernel** | `6.6.147-09648-g97ef00d8a343` (`PREEMPT_DYNAMIC`) | Built-in (`=y`): `OVERLAY_FS`, `VETH`, `BRIDGE`, `NF_NAT`, `IP_NF_NAT`, `VXLAN`, `BPF_SYSCALL`, `USER_NS`, `SECCOMP` |
| **Virtualization** | `kvm` (container: `none`) | Direct KVM guest with full root capabilities (`CapEff: 000001ffffffffff`) |
| **Devices** | `/dev/kvm`, `/dev/net/tun`, `/dev/fuse` | Present out of the box; `$USER` is pre-added to the `kvm` and `sudo` groups |
| **CPU** | 12 vCPUs (12th Gen Intel Core i5-1245U) | 4+ vCPUs recommended (first-run Substrate build compiles an Envoy Rust dynamic module + 10 Go images) |
| **Memory** | 14 GiB RAM (~8.6 GiB available before cluster start) | ~9.1 GiB total used once Kind + Substrate + AX + 2 gVisor workers are running (~4.9 GiB remains free) |
| **Root Filesystem** | `btrfs` on `/dev/vdb` (~20 GiB free before setup) | Docker 26.1.5 automatically uses `overlay2` on top of `btrfs` on kernel 6.6+; requires ~10–12 GiB during initial build |
| **Go Toolchain** | `go1.27.1 linux/amd64` (`/usr/local/go/bin/go`) | Matches `go.mod` in `google/ax` |

---

## 2. Installing Prerequisites (`docker`, `kubectl`, `kind`, `envsubst`)

### Gotcha #1: Debian 13 (`trixie`) Splits `docker.io` and `docker-cli`

In Debian 13 (`trixie`), the `docker.io` package installs only `dockerd` (the daemon), while the `/usr/bin/docker` CLI binary lives in **`docker-cli`** (a *Recommended* dependency) and BuildKit lives in **`docker-buildx`**. If you pass `--no-install-recommends` to `apt-get install docker.io`, `/usr/bin/docker` will be missing unless you explicitly include `docker-cli` and `docker-buildx`.

You also need **`gettext-base`** for `envsubst`, which `hack/setup-e2e-kind.sh` uses to substitute manifest variables.

### Step 2.1: Install OS Packages & Configure Docker

```bash
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
  ca-certificates \
  curl \
  docker-buildx \
  docker-cli \
  docker.io \
  gettext-base \
  jq \
  openssl

sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"
```

### Gotcha #2: Using `/var/run/docker.sock` Without Restarting Crostini

`sudo usermod -aG docker "$USER"` only takes effect on your next login session. To allow your current shell (and automated tools) to talk to the Docker daemon immediately without restarting the Linux container:

```bash
sudo setfacl -m "u:${USER}:rw" /var/run/docker.sock 2>/dev/null || sudo chmod 666 /var/run/docker.sock
```

Verify Docker is running with `overlay2` and `cgroupv2`:

```bash
docker info --format 'ServerVersion={{.ServerVersion}} Driver={{.Driver}} CgroupDriver={{.CgroupDriver}} CgroupVersion={{.CgroupVersion}}'
# ServerVersion=26.1.5+dfsg1 Driver=overlay2 CgroupDriver=systemd CgroupVersion=2
```

### Step 2.2: Install `kubectl` and `kind`

Install the static `linux/amd64` binaries into `/usr/local/bin`:

```bash
ARCH="$(dpkg --print-architecture)"

# Install kubectl (verified with v1.37.2)
K8S_VER="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
sudo curl -fsSL "https://dl.k8s.io/release/${K8S_VER}/bin/linux/${ARCH}/kubectl" -o /usr/local/bin/kubectl
sudo chmod +x /usr/local/bin/kubectl

# Install kind (verified with v0.27.0)
sudo curl -fsSL "https://kind.sigs.k8s.io/dl/v0.27.0/kind-linux-${ARCH}" -o /usr/local/bin/kind
sudo chmod +x /usr/local/bin/kind
```

---

## 3. Syncing Your Fork & Building AX Binaries

### Gotcha #3: SSH Agent vs. `gh` CLI Authentication on Crostini

After a Chromebook reboot, `ssh-agent` has no loaded identities (`ssh-add -l` reports `The agent has no identities`), which causes `git fetch upstream` over `git@github.com:...` to fail with `Permission denied (publickey)`. Either load your SSH key (`ssh-add ~/.ssh/id_ed25519`) or use the authenticated `gh` CLI + HTTPS remotes:

```bash
cd ~/projects/ax

# Fast-forward your GitHub fork's main branch to google/ax:main
gh repo sync ghchinoy/ax --branch main

# Fetch upstream/main and origin/main over HTTPS and update local main
git fetch https://github.com/google/ax.git main:refs/remotes/upstream/main
git fetch https://github.com/ghchinoy/ax.git main:refs/remotes/origin/main
git checkout main
git merge --ff-only upstream/main

# Verify local build and unit test suite (~18s across 16 packages)
make build
go test ./...
```

---

## 4. Provisioning Kind + Agent Substrate (`v1.0.0-rc.1`) + AX

`hack/setup-e2e-kind.sh` in `~/projects/ax` automates the entire local cluster stack:
1. Clones Agent Substrate into `.tmp/substrate` and creates a detached worktree at the `go.mod` version (`v1.0.0-rc.1`, commit `f86fde9dfb54`).
2. Starts a persistent local OCI registry container (`kind-registry` on `127.0.0.1:5001`) backed by `SUBSTRATE_IMAGE_CACHE_DIR`.
3. Publishes Substrate's 11 release images (`envoy-dataplane`, `ate-idp-server`, `ateapi`, `atecontroller`, `atelet`, `atenet`, `ateworker-gvisor`, `ateworker-microvm`, `kubernetes-secrets`, `objectstore-plugin`, `podcertcontroller`) to `localhost:5001`.
4. Creates the `ax-e2e` Kind cluster and installs `ate-system` (`ate-setup deploy ate-system`), `podcertificate-controller-system`, and `otel-system`.
5. Deploys `ax-system` (`ax-workers` gVisor `WorkerPool`, `ax-postgres`, and `ax-server`) and writes `.tmp/e2e.env`.

### Recommended Crostini Tuning

On a 14 GiB RAM Chromebook with ~20 GiB free disk:
1. **`AX_WORKER_REPLICAS=2`** *(default is `4`)*: Halves the number of idle gVisor `ax-workers` pods while still supporting multi-task concurrency and the entire E2E test suite.
2. **`SUBSTRATE_IMAGE_CACHE_DIR="$HOME/.cache/substrate-registry"`**: Persists the 538 MB of compiled Substrate `v1.0.0-rc.1` images on the host filesystem. Cold build takes **~12m00s** (compiling the Rust `substrate-envoy-egress-policy` dynamic module and 10 Go binaries); subsequent warm runs reuse the cache and complete in **~58.8s**.
3. **`docker builder prune -f` after first build**: The multi-stage Rust/Envoy Docker build leaves `1.29 GB` of intermediate BuildKit cache. Pruning it immediately reclaims `~2.3 GB` on the Crostini `btrfs` volume without affecting `~/.cache/substrate-registry`.

```bash
cd ~/projects/ax
mkdir -p "$HOME/.cache/substrate-registry"

AX_WORKER_REPLICAS=2 \
SUBSTRATE_IMAGE_CACHE_DIR="$HOME/.cache/substrate-registry" \
./hack/setup-e2e-kind.sh

# Reclaim ~1.3 GB of intermediate Rust/Envoy Docker build cache
docker builder prune -f
```

*(Or run `./crostini/setup-crostini.sh` from `~/projects/ax-experiments`, which runs Steps 1–4 automatically.)*

---

## 5. Verifying the Cluster & Running Sandboxed Tasks

Load the generated environment file into your shell:

```bash
cd ~/projects/ax
source .tmp/e2e.env
export PATH="$(dirname "$AX_BIN"):$PATH"
```

### 5.1 Inspect Running Pods across Namespaces

```bash
kubectl get pods -A
```

Observed healthy topology (28 pods across 6 namespaces):
- **`ate-system`**: `ate-api-server` (2 replicas), `ate-controller`, `ate-idp-server` (2 replicas), `atelet` DaemonSet, `atenet-egress`, `atenet-router`, `postgres-0`, `rustfs` + `rustfs-bucket-init`
- **`ax-system`**: `ax-postgres-0`, `ax-server`, `ax-workers` (2 gVisor worker replicas)
- **`podcertificate-controller-system`**: `podcertificate-controller`
- **`otel-system`**: `opentelemetry-collector`, `jaeger`, `prometheus`
- **`kube-system` & `local-path-storage`**: Kind control plane, `coredns`, `kindnet`, `local-path-provisioner`

### 5.2 Run the Interactive Lifecycle Demo (`./demo.sh`)

```bash
./demo.sh
```

Observed output on `penguin` (**7.81s** total end-to-end):
- Creates `workspace.ax.io/demo-workspace` and `task.ax.io/demo-task` (`spec.debug: true`).
- `ax resume task demo-task`: Allocates a gVisor actor (`10.244.0.22`) on Substrate and materializes `/workspace`.
- `ax ssh demo-task`: Executes commands inside the gVisor sandbox (`Linux actor 4.19.0-gvisor #1 SMP ... x86_64 GNU/Linux`) over the mTLS `atenet-router` tunnel and queries the loopback metadata server (`http://127.0.0.1:8099/metadata/v1alpha1/ax/task`).
- `ax suspend task demo-task`: Checkpoints `/workspace` to in-cluster RustFS (`gs://ate-snapshots/ax/`) and tears down the sandbox (`WORKER-IP: <none>`).

### 5.3 Verify Volume Persistence Across `ax suspend` → `ax resume`

```bash
ax resume task demo-task
ax ssh demo-task -- sh -c 'echo "hello from crostini gvisor sandbox $(uname -a)" > /workspace/crostini-proof.txt'
ax suspend task demo-task
ax resume task demo-task
ax ssh demo-task -- cat /workspace/crostini-proof.txt
# Output:
# hello from crostini gvisor sandbox Linux actor 4.19.0-gvisor #1 SMP Sun Jan 10 15:06:54 PST 2016 x86_64 GNU/Linux

ax delete task demo-task
ax delete workspace demo-workspace
```

### 5.4 Run the Full Upstream E2E Suite (`make e2e-run`)

```bash
make e2e-run
```

All 8 E2E test suites pass in **32.6s**:

```text
=== RUN   TestE2E_CLIVersionAndAutoTunnel
--- PASS: TestE2E_CLIVersionAndAutoTunnel (0.14s)
=== RUN   TestE2E_WorkspaceCRUD
--- PASS: TestE2E_WorkspaceCRUD (0.39s)
=== RUN   TestE2E_ModelCRUD
--- PASS: TestE2E_ModelCRUD (0.47s)
=== RUN   TestE2E_TaskLifecycleAndSubstrateSync
--- PASS: TestE2E_TaskLifecycleAndSubstrateSync (3.86s)
=== RUN   TestE2E_MetadataServerAndGuestExec
--- PASS: TestE2E_MetadataServerAndGuestExec (14.48s)
=== RUN   TestE2E_WorkspaceSetup_FilesAndGit
--- PASS: TestE2E_WorkspaceSetup_FilesAndGit (4.28s)
=== RUN   TestE2E_TaskSuspendAndResumePersistence
--- PASS: TestE2E_TaskSuspendAndResumePersistence (5.09s)
=== RUN   TestE2E_DescribeAndAtespaceIsolation
--- PASS: TestE2E_DescribeAndAtespaceIsolation (3.14s)
PASS
ok  	github.com/google/ax/test/e2e	32.633s
```

---

## 6. Multi-Agent Samples on Crostini (`crostini/samples/`)

Once your Kind + Agent Substrate + AX cluster is running, you can run two multi-task samples that demonstrate how isolated gVisor sandboxes share data and converse over **A2A gRPC**.

### 6.1 Sample 1: Zero-Key Two-Sandbox Handoff & RustFS Checkpoint Pipeline (`01-sandbox-relay.sh`)

Requires no LLM API key and uses the default `ax-task-runner` image:
1. **`repo-scanner` (Task 1)** binds `scanner-ws` (cloning `/opt/ax-e2e-sample-repo.git` into `/workspace/repo`), computes SHA-256 digests and commit metadata inside gVisor Sandbox A (`4.19.0-gvisor`), writes `/workspace/handoff.json`, and suspends (`ax suspend task repo-scanner`) to release its gVisor worker and checkpoint to RustFS.
2. **`release-builder` (Task 2)** resumes in gVisor Sandbox B, receives `handoff.json`, verifies every file's SHA-256 digest against its own clone, writes `/workspace/RELEASE_NOTES.md`, suspends to RustFS, resumes, and confirms `/workspace/RELEASE_NOTES.md` survived across the checkpoint.

```bash
cd ~/projects/ax-experiments
./crostini/samples/01-sandbox-relay.sh
```

Measured runtime on `penguin`: **`9.68s`**.

---

### 6.2 Sample 2: Two Declarative `genkit-runner` Agents Conversing Over A2A gRPC (`02-genkit-a2a-grpc.sh`)

Uses `cmd/runners/genkit-runner` (from the `feat/genkit-runner` branch of `ghchinoy/ax`), where both tasks run the **exact same `localhost:5001/genkit-runner` image** and define their persona, model (`vertexai/gemini-2.5-flash`), and middleware (`genkit-middleware/filesystem`, `genkit-middleware/skills`) purely in YAML (`Task.spec.config`).

#### How A2A gRPC Transport Works Across `atenet-router` and `genkit-runner`

1. **In-Sandbox `h2c` gRPC Multiplexing on Port 80**:
   - Inside each task container, `internal/metadata/server.go` listens on port `80` with `HTTP/1.1` + unencrypted `HTTP/2` (`h2c`).
   - When `spec.debug: true`, the metadata server routes `/ate.guest.*` gRPC calls (`ax ssh`) to the guest `grpc.Server`, while delegating other `application/grpc` paths (`/lf.a2a.v1.A2AService/*` and `/a2a.v1.A2AService/*`) to `genkit-runner`'s A2A `grpc.Server` (`a2agrpcv1.NewHandler(a2aHandler).RegisterWith(a2aGRPCServer)`).
2. **mTLS Routing & Wake-on-Request via `atenet-router`**:
   - The Go orchestrator ([`crostini/samples/a2a-duo/main.go`](./samples/a2a-duo/main.go)) dials `atenet-router.ate-system.svc:443` over mTLS using the cached `podidentity` client certificate (`~/.ax/tunnels/kind-ax-e2e-ax-system-ax-server-router-tls.json`) and constructs two `a2aclient.Client` instances with `a2agrpcv1.WithGRPCTransport(...)`.
   - Each client injects `ate-target-actor: default/<task>` into outgoing gRPC metadata (`metadata.AppendToOutgoingContext`).
3. **Gotcha #4: Substrate `v1.0.0-rc.1` Default-Deny Egress (`EgressPolicy`)**:
   - In Agent Substrate `v1.0.0-rc.1`, gVisor sandboxes use `atelet` (`169.254.17.1`) for DNS and `atenet-egress` for outbound connections, which denies all external hostnames by default (`curl: (6) Could not resolve host: oauth2.googleapis.com`).
   - `a2a-duo` calls `CreateActorEgressPolicy` on `api.ate-system.svc` to attach a `default` `EgressPolicy` with a `TlsPassthroughRule` for `*.googleapis.com:443` to both `default/coder-agent` and `default/auditor-agent`.

#### Running Sample 2

```bash
# 1. Build and push the genkit-runner image from feat/genkit-runner (once)
cd ~/projects/ax
git checkout feat/genkit-runner
make push-genkit-image \
  CONTAINER_CLI=docker \
  GENKIT_REPO=localhost:5001/genkit-runner \
  GENKIT_BASE_IMAGE=localhost:5001/ax-task-runner:e2e

# 2. Run the 2-agent A2A gRPC workflow
cd ~/projects/ax-experiments
./crostini/samples/02-genkit-a2a-grpc.sh
```

#### Verified Multi-Turn Execution Flow (**`35.23s`** total)

1. **Step 1 — A2A gRPC AgentCard Discovery (`lf.a2a.v1.A2AService/GetExtendedAgentCard`)**:
   ```text
   ✔ Coder AgentCard   : name="coder_agent" version="1.0.0" protocols=[GRPC(1.0) JSONRPC(1.0)]
   ✔ Auditor AgentCard : name="auditor_agent" version="1.0.0" protocols=[GRPC(1.0) JSONRPC(1.0)]
   ```
2. **Step 2 — Turn 1 (`Orchestrator → coder-agent` over A2A gRPC, `contextId="coder-session-1"`)**:
   - `coder-agent` (on gVisor worker `10.244.0.22`) reads `README.md` and `retry_test.go`, patches `ComputeJitter` to guard against `maxJitter <= 0`, and returns the explanation over A2A gRPC.
3. **Step 3 — Turn 2 (`coder-agent → auditor-agent` over A2A gRPC, `contextId="audit-session-1"`)**:
   - `auditor-agent` (on gVisor worker `10.244.0.23`) loads `.agents/skills/security-rubric/SKILL.md`, writes `/workspace/AUDIT_VERDICT.md`, and returns `VERDICT: NEEDS_WORK` requesting an explicit negative-bound assertion (`ComputeJitter(-5) == 0`).
4. **Step 4 — Scale-to-Zero (`ax suspend task coder-agent`)**:
   - Checkpoints `coder-agent`'s `/workspace` (including `/workspace/.genkit/snapshots`) to RustFS and tears down its gVisor container.
5. **Step 5 — Turn 3 (`auditor-agent → coder-agent` over A2A gRPC with Wake-on-Request, `contextId="coder-session-1"`)**:
   - Sending the A2A gRPC `SendMessage` request while `coder-agent` is `Suspended` causes `atenet-router` to wake `coder-agent` automatically, restore `/workspace` from RustFS, add the `ComputeJitter(-5)` assertion to `/workspace/retry_test.go`, write `/workspace/HANDOFF_COMPLETE.md`, and confirm from its Turn 1 session snapshot that it fixed `retry_test.go`.

---

## 7. Empirical Timings & Resource Footprint Summary

| Metric / Operation | Measured Value on Crostini (`i5-1245U`, 12 vCPU, 14 GiB RAM) |
|---|---|
| **Unit test suite (`go test ./...`)** | `17.8s` (17 packages on `feat/genkit-runner`) |
| **Cold `setup-e2e-kind.sh` (builds Substrate `v1.0.0-rc.1` from source + caches images)** | `12m 00.5s` |
| **Warm `setup-e2e-kind.sh` (reuses `~/.cache/substrate-registry` + Kind cluster)** | `58.8s` |
| **Full `./demo.sh` lifecycle (apply → resume → 3× `ax ssh` → RustFS snapshot suspend)** | `7.81s` |
| **Sample 1 (`01-sandbox-relay.sh`, 2-task gVisor handoff + RustFS checkpoint)** | `9.68s` |
| **Sample 2 (`02-genkit-a2a-grpc.sh`, 2 Genkit agents over A2A gRPC + wake-on-request)** | `35.23s` |
| **Full E2E suite (`make e2e-run`, 8 test cases)** | `32.63s` |
| **VM RAM used (idle before cluster → full cluster running)** | `5.5 GiB` → `9.1 GiB` (`4.9 GiB` available) |
| **Disk footprint (`~/.cache/substrate-registry` / `.tmp` / Kind containerd volume)** | `538 MB` / `423 MB` / `4.59 GB` (`8.5 GiB` free on `/` after `docker builder prune -f`) |

---

## 8. Pausing or Cleaning Up to Reclaim Chromebook Battery & RAM

When you finish working for the day on a Chromebook:

- **Option A — Pause the Kind node without losing cluster state** (stops CPU/RAM drain immediately and resumes in ~10s):
  ```bash
  docker stop ax-e2e-control-plane kind-registry
  # Later, to resume:
  docker start kind-registry ax-e2e-control-plane
  ```
- **Option B — Delete the Kind cluster completely** (frees the `4.6 GB` Kind containerd volume while keeping `~/.cache/substrate-registry` for a fast ~2–3 min recreate):
  ```bash
  cd ~/projects/ax && make e2e-cleanup
  ```
