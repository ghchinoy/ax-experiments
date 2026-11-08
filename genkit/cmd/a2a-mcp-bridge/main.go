// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// Command a2a-mcp-bridge is an in-sandbox stdio Model Context Protocol (MCP)
// server that exposes `delegate_to_actor`, allowing a Genkit task running
// inside a gVisor sandbox to wake and invoke another AX task directly through
// `atenet-router.ate-system.svc.cluster.local:443` over mTLS using the A2A
// gRPC transport (lf.a2a.v1.A2AService).
package main

import (
	"bufio"
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/ghchinoy/ax-experiments/genkit/internal/axclient"
)

type rpcRequest struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      any             `json:"id,omitempty"`
	Method  string          `json:"method"`
	Params  json.RawMessage `json:"params,omitempty"`
}

type rpcResponse struct {
	JSONRPC string `json:"jsonrpc"`
	ID      any    `json:"id"`
	Result  any    `json:"result,omitempty"`
	Error   any    `json:"error,omitempty"`
}

type callToolParams struct {
	Name      string         `json:"name"`
	Arguments map[string]any `json:"arguments"`
}

type delegationLogRecord struct {
	Time         string `json:"time"`
	TargetActor  string `json:"target_actor"`
	ContextID    string `json:"context_id"`
	RouterAddr   string `json:"router_addr"`
	CertNotAfter string `json:"cert_not_after"`
	DurationMS   int64  `json:"duration_ms"`
	Status       string `json:"status"`
	ReplyChars   int    `json:"reply_chars,omitempty"`
	Error        string `json:"error,omitempty"`
}

func main() {
	var (
		routerAddr string
		atespace   string
		tlsFile    string
		logFile    string
	)
	flag.StringVar(&routerAddr, "router", axclient.InClusterRouterURL, "In-cluster atenet-router address")
	flag.StringVar(&atespace, "atespace", "default", "Default atespace for target actors")
	flag.StringVar(&tlsFile, "tls-file", "/workspace/.ax-router-tls.json", "Path to mounted router mTLS JSON bundle")
	flag.StringVar(&logFile, "log-file", "/workspace/.genkit/mcp-delegation.jsonl", "Path to structured JSONL delegation log")
	flag.Parse()

	scanner := bufio.NewScanner(os.Stdin)
	scanner.Buffer(make([]byte, 0, 64*1024), 4*1024*1024)
	enc := json.NewEncoder(os.Stdout)

	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" {
			continue
		}
		var req rpcRequest
		if err := json.Unmarshal([]byte(line), &req); err != nil {
			continue
		}
		if req.ID == nil {
			// Notification (e.g. notifications/initialized)
			continue
		}

		switch req.Method {
		case "initialize":
			_ = enc.Encode(rpcResponse{
				JSONRPC: "2.0",
				ID:      req.ID,
				Result: map[string]any{
					"protocolVersion": "2024-11-05",
					"capabilities": map[string]any{
						"tools": map[string]any{},
					},
					"serverInfo": map[string]any{
						"name":    "a2a-mcp-bridge",
						"version": "1.0.0",
					},
				},
			})

		case "tools/list":
			_ = enc.Encode(rpcResponse{
				JSONRPC: "2.0",
				ID:      req.ID,
				Result: map[string]any{
					"tools": []map[string]any{{
						"name":        "delegate_to_actor",
						"description": "Wakes (if suspended) and sends a task prompt to another AX agent task in the cluster over A2A gRPC (lf.a2a.v1.A2AService) via atenet-router mTLS, returning the specialist agent's response.",
						"inputSchema": map[string]any{
							"type": "object",
							"properties": map[string]any{
								"actor": map[string]any{
									"type":        "string",
									"description": "Target AX task/actor name (e.g. 'security-specialist').",
								},
								"prompt": map[string]any{
									"type":        "string",
									"description": "Detailed prompt or code snippet for the specialist agent to analyze.",
								},
								"context_id": map[string]any{
									"type":        "string",
									"description": "Optional A2A session contextId for correlation.",
								},
							},
							"required": []string{"actor", "prompt"},
						},
					}},
				},
			})

		case "tools/call":
			var p callToolParams
			if err := json.Unmarshal(req.Params, &p); err != nil || p.Name != "delegate_to_actor" {
				_ = enc.Encode(rpcResponse{
					JSONRPC: "2.0",
					ID:      req.ID,
					Error:   map[string]any{"code": -32601, "message": "unknown tool"},
				})
				continue
			}
			actorName, _ := p.Arguments["actor"].(string)
			promptText, _ := p.Arguments["prompt"].(string)
			contextID, _ := p.Arguments["context_id"].(string)
			if contextID == "" {
				contextID = fmt.Sprintf("in-cluster-%s-%d", actorName, time.Now().Unix())
			}

			reply, err := invokeSpecialistA2A(routerAddr, atespace, actorName, contextID, promptText, tlsFile, logFile)
			if err != nil {
				_ = enc.Encode(rpcResponse{
					JSONRPC: "2.0",
					ID:      req.ID,
					Result: map[string]any{
						"isError": true,
						"content": []map[string]any{{
							"type": "text",
							"text": fmt.Sprintf("A2A gRPC delegation to %s failed: %v", actorName, err),
						}},
					},
				})
				continue
			}

			_ = enc.Encode(rpcResponse{
				JSONRPC: "2.0",
				ID:      req.ID,
				Result: map[string]any{
					"content": []map[string]any{{
						"type": "text",
						"text": reply,
					}},
				},
			})

		default:
			_ = enc.Encode(rpcResponse{
				JSONRPC: "2.0",
				ID:      req.ID,
				Result:  map[string]any{},
			})
		}
	}
}

func invokeSpecialistA2A(routerAddr, atespace, actorName, contextID, promptText, tlsFile, logFile string) (string, error) {
	start := time.Now()
	targetActor := actorName
	if !strings.Contains(targetActor, "/") {
		targetActor = atespace + "/" + targetActor
	}

	tlsCfg, notAfter, err := axclient.LoadRouterTLSFromFile(tlsFile)
	if err != nil {
		appendLog(logFile, delegationLogRecord{
			Time:        time.Now().UTC().Format(time.RFC3339Nano),
			TargetActor: targetActor,
			ContextID:   contextID,
			RouterAddr:  routerAddr,
			DurationMS:  time.Since(start).Milliseconds(),
			Status:      "tls_error",
			Error:       err.Error(),
		})
		return "", err
	}

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()

	client, err := axclient.NewActorA2AGRPCClient(ctx, routerAddr, tlsCfg, targetActor)
	if err != nil {
		appendLog(logFile, delegationLogRecord{
			Time:         time.Now().UTC().Format(time.RFC3339Nano),
			TargetActor:  targetActor,
			ContextID:    contextID,
			RouterAddr:   routerAddr,
			CertNotAfter: notAfter.UTC().Format(time.RFC3339),
			DurationMS:   time.Since(start).Milliseconds(),
			Status:       "client_init_error",
			Error:        err.Error(),
		})
		return "", err
	}
	defer client.Destroy()

	reply, elapsed, err := axclient.SendA2AGRPCMessage(ctx, client, contextID, promptText, true)
	if err != nil {
		appendLog(logFile, delegationLogRecord{
			Time:         time.Now().UTC().Format(time.RFC3339Nano),
			TargetActor:  targetActor,
			ContextID:    contextID,
			RouterAddr:   routerAddr,
			CertNotAfter: notAfter.UTC().Format(time.RFC3339),
			DurationMS:   time.Since(start).Milliseconds(),
			Status:       "rpc_error",
			Error:        err.Error(),
		})
		return "", err
	}

	appendLog(logFile, delegationLogRecord{
		Time:         time.Now().UTC().Format(time.RFC3339Nano),
		TargetActor:  targetActor,
		ContextID:    contextID,
		RouterAddr:   routerAddr,
		CertNotAfter: notAfter.UTC().Format(time.RFC3339),
		DurationMS:   elapsed.Milliseconds(),
		Status:       "ok",
		ReplyChars:   len(reply),
	})
	return reply, nil
}

func appendLog(path string, rec delegationLogRecord) {
	if path == "" {
		return
	}
	_ = os.MkdirAll(filepath.Dir(path), 0o755)
	f, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644)
	if err != nil {
		return
	}
	defer f.Close()
	_ = json.NewEncoder(f).Encode(rec)
}
