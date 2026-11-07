# `ax-trace` Swarm Trace Recorder Package

## Overview
Go CLI (`ax-trace`) that tails `ax-server` and `ate-local` log files alongside recipe-emitted JSONL events (`AX_TRACE_RECIPE`), normalizing them into the unified replay schema defined in [`../SCHEMA.md`](../SCHEMA.md) for [`../web/README.md`](../README.md).

## Interface
- **Binary Entrypoint**: `main.go` (`ax-trace`)
- **Flags**:
  - `-out <path>`: Output `.jsonl` trace file path (default `trace.jsonl`).
  - `-ax-dir <path>`: Path to `.ax-local` state directory containing `logs/ax-server.log` and `logs/ate-local.log`.

## Invariants
- Preserves chronological ordering of `run.start`, `node.add`, `edge.exec`, `edge.msg`, `note`, and `run.end` events.
- Flushes each JSONL line atomically on write and exits cleanly on `SIGINT` / `SIGTERM`.

## Side Effects
- Reads `.ax-local/logs/*.log` and writes normalized JSONL events to the `-out` file path.

## Verification
- Run: `go -C viz/recorder vet ./... && go -C viz/recorder build -o /dev/null ./...`
