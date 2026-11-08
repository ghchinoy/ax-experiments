# `axclient` Substrate Egress & A2A gRPC Client Package

## Overview
Shared Go library (`github.com/ghchinoy/ax-experiments/genkit/internal/axclient`) providing Agent Substrate `EgressPolicy` provisioning (`TlsPassthroughRule` and `HttpRule`), `atenet-router` mTLS credential loading, and A2A gRPC (`lf.a2a.v1.A2AService`) streaming client helpers.

## Interface
- **Exported Symbols (`client.go`)**:
  - `EgressOptions`: Configures optional TLS passthrough (`IncludeRouter`, `IncludeGitHub`, `IncludeDGem`, `ExtraTLSHosts`) and cleartext HTTP (`ExtraHTTPHosts`, `HTTPPorts`) rules.
  - `EnsureActorEgress(ctx, kubeContext, axNamespace, atespace, actors, includeRouter)` & `EnsureActorEgressWithOptions(..., opts)`
  - `LoadRouterTLSFromFile(path)` & `RefreshAndLoadRouterTLS(ctx, kubeContext, axNamespace, axBin, atespace, probeTask)`
  - `SendA2AMessage(ctx, routerAddr, tlsCfg, atespace, actor, contextID, prompt)`
  - `StartPortForward(ctx, kubeContext, namespace, target, remotePort)`

## Invariants
- Validates cached `atenet-router` mTLS certificates against `ExpiresAt` with a 2-minute safety margin before reuse.
- Updates existing `"default"` `EgressPolicy` records idempotently when `CreateActorEgressPolicy` returns `AlreadyExists`.

## Side Effects
- Spawns short-lived `kubectl port-forward` subprocesses and calls `ateapipb.ControlClient` (`CreateActorEgressPolicy` / `UpdateActorEgressPolicy`) and `lf.a2a.v1.A2AService`.

## Verification
- Run: `go -C genkit vet ./internal/axclient && go -C genkit build -o /dev/null ./internal/axclient`
