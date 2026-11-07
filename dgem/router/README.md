# `dgem-router` Component Package

## Overview
Standalone Genkit Go `v1.14.0` CLI (`dgem-router`) that runs inside the `dgem-router` AX Apple `container` microVM and evaluates [`../templates/specialist_router.json.tmpl`](../templates/specialist_router.json.tmpl) in a single diffusion forward pass via `dgemgenkit.EndpointConfig` and `systemonex.SystemOne`.

## Interface
- **Binary Entrypoint**: `main.go` (`dgem-router`)
- **Flags & Environment Variables**:
  - `-query <string>` *(required)*: Incoming user request or incident description to classify.
  - `-template <path>`: Path to the routing policy template (default `/opt/dgem/templates/specialist_router.json.tmpl`).
  - `-gateway-url <url>` (`DGEM_GATEWAY_URL` / `DGEM_SYSTEMONE_URL`): Direct `dgem serve` gateway or `/v1/systemone` URL (e.g., `http://192.168.64.1:8095`).
  - `-url <url>` (`DGEM_URL`): Upstream `/v1` endpoint when `DGEM_GATEWAY_URL` is unset (default `http://127.0.0.1:8080/v1`).
  - `-model <id>` (`DGEM_MODEL`): Model identifier (default `diffgemma-26b-a4b-it-q4`).
  - `-backend <target>` (`DGEM_BACKEND`): Optional `X-DGem-Backend` routing header (`vertex_first`, `vertex`, `cloudrun`, `local`).
- **Stdout Contract**: Emits a pretty-printed `RouteDecision` JSON object containing `specialist`, `confidence`, `hesitation` ($H / \ln 3$), `band` (`Clear` | `Unsure` | `Very unsure`), `cross_domain`, `urgent`, `severity`, `wall_ms`, `probabilities`, and `targets` (`[]string` of AX Task names).

## Invariants
- Selects a single target (`targets` length 1) when `hesitation < 0.16`, `cross_domain == "no"`, and the runner-up option probability is `< 0.20`.
- Selects the top-2 targets (`targets` length 2) when `hesitation >= 0.16`, `cross_domain == "yes"`, or the runner-up option probability is `>= 0.20`.
- Exits non-zero if `-query` is empty, the `specialist` slot is missing from the rendered template, or no AX Task maps to the winning choice.

## Side Effects
- Sends a single `POST /v1/systemone` HTTP request to the configured `dgem` gateway or in-process `/v1` adapter.
- Appends a single structured `"genkit otel span"` log line to `/proc/1/fd/2` (container PID 1 stderr) when present so `container logs -f` in AX Central captures live System-1 routing spans executed over `ax ssh`. Performs no other local disk writes.

## Verification
- Run: `go -C dgem/router vet ./... && go -C dgem/router build -o /dev/null ./...`
