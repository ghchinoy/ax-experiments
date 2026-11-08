SHELL := /bin/bash

# OKF v0.2 tooling:
#   binder:    https://github.com/ghchinoy/binder    (go install github.com/ghchinoy/binder@latest)
#   okf-proto: https://github.com/ghchinoy/okf-proto (go install github.com/ghchinoy/okf-proto/cmd/okf-proto@latest)
BINDER ?= binder
OKF_PROTO ?= okf-proto
AX_REPO ?= $(HOME)/projects/ax

.PHONY: help check okf-validate stack-up stack-status stack-down agent-image build-recorder viz-install viz-build viz-dev viz-preview genkit-apple dgem-up dgem-status dgem-down dgem-cloudrun-down dgem-01 dgem-02 dgem-03 swarm-01 swarm-02 swarm-03 swarm-04 swarm-05 swarm-06 swarm-07 swarm-08

help:
	@echo "Targets:"
	@echo "  make stack-up         Start local AX + ate-local stack (in $(AX_REPO))"
	@echo "  make stack-status     Show status of local AX + ate-local stack"
	@echo "  make stack-down       Stop local AX + ate-local stack"
	@echo "  make check            Run all static verification gates (OKF v0.2, shell lint, Go recorder)"
	@echo "  make okf-validate     Validate OKF v0.2 bundle with binder and okf-proto"
	@echo "  make agent-image      Build ax-agent-local:latest in Apple container"
	@echo "  make genkit-apple     Run Genkit Go runner (#538) E2E in Apple container microVM"
	@echo "  make dgem-up          Ensure both dgem (:8080/:8095) and AX (:8090) local stacks are up"
	@echo "  make dgem-status      Show status of both dgem and AX local stacks"
	@echo "  make dgem-down        Stop both dgem and AX local stacks"
	@echo "  make dgem-cloudrun-down Tear down Cloud Run GPU service and switch :8095 gateway back to local Metal (:8080)"
	@echo "  make dgem-01          Run dgem + Genkit systemonex & ToolApproval inside Apple container"
	@echo "  make dgem-02          Run declarative genkit-runner + dgem Streamable HTTP MCP in Apple container"
	@echo "  make dgem-03          Run 1-to-3 Hesitation-gated scale-to-zero specialist router swarm"
	@echo "  make swarm-01         Run 01-hello-swarm (8 parallel microVMs)"
	@echo "  make swarm-02         Run 02-repo-inspector (Workspace git clones)"
	@echo "  make swarm-03         Run 03-seed-matrix (6-node parameter sweep)"
	@echo "  make swarm-04         Run 04-review-panel (3 Gemini code reviewers)"
	@echo "  make swarm-05         Run 05-debate (Adversarial Proposer & Critic)"
	@echo "  make swarm-06         Run 06-map-reduce (3 Mappers + 1 Reducer)"
	@echo "  make swarm-07         Run 07-suspend-resume (Volume persistence lifecycle)"
	@echo "  make swarm-08         Run 08-spec-config-metadata (Task.spec.config & loopback metadata)"
	@echo "  make build-recorder   Build viz/recorder/ax-trace"
	@echo "  make viz-build        Typecheck and build the web visualizer"
	@echo "  make viz-preview      Serve the built web visualizer locally"

stack-up:
	@if [[ ! -x "$(AX_REPO)/examples/ate_local/local-stack.sh" ]]; then \
		echo "Error: $(AX_REPO)/examples/ate_local/local-stack.sh not found." >&2; \
		echo "Ensure $(AX_REPO) is checked out on branch 'feat/ate-local-apple-container'." >&2; \
		exit 1; \
	fi
	"$(AX_REPO)/examples/ate_local/local-stack.sh" up

stack-status:
	@"$(AX_REPO)/examples/ate_local/local-stack.sh" status

stack-down:
	@"$(AX_REPO)/examples/ate_local/local-stack.sh" down

check: okf-validate
	bash -n swarm/*.sh genkit/*.sh dgem/*.sh crostini/*.sh crostini/samples/*.sh
	cd viz/recorder && go build -o /dev/null ./... && go vet ./...
	cd crostini/samples/a2a-duo && go build -o /dev/null ./... && go vet ./...
	cd dgem/router && go build -o /dev/null ./... && go vet ./...

okf-validate:
	$(BINDER) validate okf --strict
	$(BINDER) review okf --strict --require-tier human-reviewed
	$(OKF_PROTO) export okf --format json >/dev/null

agent-image:
	container build -t ax-agent-local:latest -f swarm/agent-image/Containerfile swarm/agent-image

genkit-apple:
	./genkit/run-apple-container.sh

dgem-up:
	./dgem/ensure-stack.sh up

dgem-status:
	./dgem/ensure-stack.sh status

dgem-down:
	./dgem/ensure-stack.sh down

dgem-cloudrun-down:
	./dgem/ensure-stack.sh cloudrun-down

dgem-01:
	./dgem/01-tool-approval-microvm.sh

dgem-02:
	./dgem/02-mcp-triage-agent.sh

dgem-03:
	./dgem/03-specialist-router.sh

build-recorder:
	cd viz/recorder && go build -o ax-trace main.go

viz-install:
	cd viz/web && pnpm install

viz-build:
	cd viz/web && pnpm build

viz-dev:
	cd viz/web && pnpm dev

viz-preview:
	cd viz/web && pnpm preview

swarm-01:
	./swarm/01-hello-swarm.sh

swarm-02:
	./swarm/02-repo-inspector.sh

swarm-03:
	./swarm/03-seed-matrix.sh

swarm-04:
	./swarm/04-review-panel.sh

swarm-05:
	./swarm/05-debate.sh

swarm-06:
	./swarm/06-map-reduce.sh

swarm-07:
	./swarm/07-suspend-resume.sh

swarm-08:
	./swarm/08-spec-config-metadata.sh
