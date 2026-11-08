# `a2a-mcp-bridge` In-Sandbox A2A gRPC MCP Server Package

## Overview
Static Go stdio Model Context Protocol (MCP) server (`/usr/local/bin/a2a-mcp-bridge`) that runs inside an AX sandbox and exposes the `delegate_to_actor` MCP tool, allowing a Genkit coordinator task to wake and invoke suspended sibling AX tasks over in-cluster `atenet-router.ate-system.svc.cluster.local:443` mTLS using A2A gRPC (`lf.a2a.v1.A2AService`).

## Interface
- **Binary Entrypoint**: `main.go` (`a2a-mcp-bridge`)
- **MCP Tool Exposed**:
  - `delegate_to_actor(actor, prompt, context_id)` — Sends a streaming A2A gRPC message to `<atespace>/<actor>` via `atenet-router:443` and returns the specialist's text reply.
- **Flags & Environment Variables**:
  - `--atespace` (`AX_ATESPACE`, default `"default"`): Target atespace for actor routing.
  - `--router-addr` (`AX_ROUTER_ADDR`, default `"atenet-router.ate-system.svc.cluster.local:443"`): In-cluster router address.
  - `--tls-file` (`AX_ROUTER_TLS_FILE`, default `"/workspace/.ax-router-tls.json"`): Cached router mTLS bundle path.
  - `--log-file` (`AX_MCP_DELEGATION_LOG`, default `"/workspace/.genkit/mcp-delegation.jsonl"`): JSONL telemetry output path.

## Invariants
- Communicates over line-delimited JSON-RPC 2.0 on `stdin`/`stdout`; never writes non-JSON diagnostic output to `stdout`.
- Verifies that the router mTLS client certificate in `--tls-file` has not expired before dialing `atenet-router:443`.

## Side Effects
- Dials `--router-addr` over mTLS (`ate-target-actor: <atespace>/<actor>`) and appends structured delegation telemetry records to `/workspace/.genkit/mcp-delegation.jsonl`.

## Verification
- Run: `go -C genkit vet ./cmd/a2a-mcp-bridge && go -C genkit build -o /dev/null ./cmd/a2a-mcp-bridge`
