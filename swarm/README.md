# AX Agent Swarm Kit on Apple Container

> **OKF v0.2 Track Metadata & Lineage**: [`okf/swarm.md`](../okf/swarm.md) · **Bundle Index**: [`okf/index.md`](../okf/index.md)

This directory contains standalone recipes demonstrating **multi-agent swarms, parallel execution, and sandbox metadata boundaries** running on **Apple `container`** via [`ate-local`](/ate-local/README.md), completely outside Kubernetes. For a deep-dive walkthrough with measured outputs and the 3 swarm patterns, see [`GUIDE.md`](/swarm/GUIDE.md).

---

## Prerequisites

1. **Local AX Stack Running**:
   In your `ax` checkout directory (`feat/ate-local-apple-container` branch), run:
   ```bash
   make local-up
   source .ax-local/env
   ```
2. **Build the Local Swarm Agent Image**:
   (Required for recipes 02, 04, 05, and 06)
   ```bash
   container build -t ax-agent-local:latest -f ~/projects/ax-experiments/swarm/agent-image/Containerfile ~/projects/ax-experiments/swarm/agent-image
   ```
3. **Set your Gemini API Key**:
   (Required for AI agent recipes 04, 05, and 06)
   ```bash
   export GEMINI_API_KEY="AIzaSy..."
   ```

---

## Recipe Catalog

| Recipe | Description | Needs API Key? | What It Demonstrates |
|---|---|:---:|---|
| [`01-hello-swarm.sh`](./01-hello-swarm.sh) | 8 parallel microVM tasks | **No** | Parallel provisioning, dynamic `vmnet` bridge IP allocation (`192.168.64.x`), host fan-out. |
| [`02-repo-inspector.sh`](./02-repo-inspector.sh) | 3 parallel tasks with Workspace git clones | **No** | Single-workspace binding (#496), git repository cloning, isolated code analysis. |
| [`03-seed-matrix.sh`](./03-seed-matrix.sh) | 6 parallel tasks with stochastic seeds | **No** | Parameter sweep / fuzz matrix testing across isolated environments. |
| [`04-review-panel.sh`](./04-review-panel.sh) | 3 specialized AI review agents | **Yes** | Multi-agent review panel: Security Auditor, Go Readability Mentor, and Performance Engineer. |
| [`05-debate.sh`](./05-debate.sh) | 2 agents in an adversarial debate | **Yes** | Multi-turn agent communication mediated by the host orchestrator across separate microVMs. |
| [`06-map-reduce.sh`](./06-map-reduce.sh) | 3 Mapper agents + 1 Reducer agent | **Yes** | Scatter-gather pattern: mappers analyze different topics; reducer synthesizes into executive takeaway. |
| [`07-suspend-resume.sh`](./07-suspend-resume.sh) | Single-task hibernation lifecycle | **No** | Proves filesystem state survives across `ax suspend` and `ax resume` while in-memory processes reboot. |
| [`08-spec-config-metadata.sh`](./08-spec-config-metadata.sh) | Declarative `spec.config` & loopback metadata | **No** | Exercises `Task.spec.config` (`google.protobuf.Struct`, #523), inlined Workspace files, and the `127.0.0.1:8099` loopback metadata boundary (#479). |

---

## Running a Recipe

```bash
# Example: Run the 8-node Hello Swarm
~/projects/ax-experiments/swarm/01-hello-swarm.sh

# Example: Run the Declarative Spec.Config & Loopback Metadata demo
~/projects/ax-experiments/swarm/08-spec-config-metadata.sh

# Example: Run the Code Review Panel
~/projects/ax-experiments/swarm/04-review-panel.sh
```

All recipes automatically clean up their tasks upon exit.
