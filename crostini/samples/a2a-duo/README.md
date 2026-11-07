# `a2a-duo` Two-Agent A2A gRPC Sample Package

## Overview
Standalone Go sample (`a2a-duo`) for [`../../README.md`](../../README.md) demonstrating two Genkit Go agents communicating over the Agent2Agent (`lf.a2a.v1.A2AService`) gRPC and JSON-RPC protocols inside a Crostini / Agent Substrate environment.

## Interface
- **Binary Entrypoint**: `main.go` (`a2a-duo`)
- **Environment Variables**:
  - `GEMINI_API_KEY` or `GOOGLE_CLOUD_PROJECT`: Credentials for the backing Gemini model.

## Invariants
- Starts an in-process listener for the specialist A2A server before dispatching the coordinator turn.

## Side Effects
- Opens ephemeral localhost TCP listeners for A2A gRPC/HTTP transport and calls the configured Gemini API endpoint.

## Verification
- Run: `go -C crostini/samples/a2a-duo vet ./... && go -C crostini/samples/a2a-duo build -o /dev/null ./...`
