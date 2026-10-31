SHELL := /bin/bash

.PHONY: help agent-image build-recorder viz-install viz-build viz-dev viz-preview swarm-01 swarm-02 swarm-03 swarm-04 swarm-05 swarm-06 swarm-07 swarm-08

help:
	@echo "Targets:"
	@echo "  make agent-image      Build ax-agent-local:latest in Apple container"
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

agent-image:
	container build -t ax-agent-local:latest -f swarm/agent-image/Containerfile swarm/agent-image

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
