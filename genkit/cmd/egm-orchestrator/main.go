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

// Command egm-orchestrator drives the two multi-agent Genkit Go examples on AX
// and Agent Substrate over A2A gRPC (lf.a2a.v1.A2AService/SendStreamingMessage):
//   - `--mode=egm-panel`: Example A (1 Stateful Elephant + 3 Stateless Goldfish
//     reviewers with Dotprompt output.schema and wave-scoped contextId isolation)
//   - `--mode=in-cluster-delegation`: Example B (Coordinator task invoking an
//     in-sandbox MCP tool that wakes a suspended specialist task directly via
//     in-cluster atenet-router:443 mTLS over A2A gRPC)
package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"strings"
	"sync"
	"time"

	"github.com/a2aproject/a2a-go/v2/a2a"
	"github.com/ghchinoy/ax-experiments/genkit/internal/axclient"
)

type goldfishFinding struct {
	Severity       string `json:"severity"`
	Title          string `json:"title"`
	Recommendation string `json:"recommendation"`
}

type goldfishReviewOutput struct {
	Reviewer string            `json:"reviewer"`
	Verdict  string            `json:"verdict"`
	Summary  string            `json:"summary"`
	Findings []goldfishFinding `json:"findings"`
}

func main() {
	var (
		mode        string
		atespace    string
		axNamespace string
		kubeContext string
		axBin       string
	)
	flag.StringVar(&mode, "mode", "egm-panel", "Execution mode: egm-panel | in-cluster-delegation")
	flag.StringVar(&atespace, "atespace", "default", "Atespace for the tasks")
	flag.StringVar(&axNamespace, "ax-namespace", "ax-system", "Namespace where ax-server is deployed")
	flag.StringVar(&kubeContext, "context", "kind-ax-e2e", "Kubernetes context")
	flag.StringVar(&axBin, "ax-bin", "", "Path to the ax CLI binary")
	flag.Parse()

	ctx, cancel := context.WithTimeout(context.Background(), 6*time.Minute)
	defer cancel()

	switch mode {
	case "egm-panel":
		if err := runEGMPanel(ctx, kubeContext, axNamespace, atespace, axBin); err != nil {
			fatalf("egm-panel failed: %v", err)
		}
	case "in-cluster-delegation":
		if err := runInClusterDelegation(ctx, kubeContext, axNamespace, atespace); err != nil {
			fatalf("in-cluster-delegation failed: %v", err)
		}
	default:
		fatalf("unknown --mode=%q (want egm-panel or in-cluster-delegation)", mode)
	}
}

func runEGMPanel(ctx context.Context, kubeContext, axNamespace, atespace, axBin string) error {
	elephantTask := "elephant-architect"
	goldfishTasks := []string{
		"goldfish-design",
		"goldfish-catalyst",
		"goldfish-comprehension",
	}
	allActors := append([]string{elephantTask}, goldfishTasks...)

	fmt.Printf("\n==> [EGM Step 1] Configuring Substrate EgressPolicy (*.googleapis.com:443) for 1 Elephant + 3 Goldfish actors...\n")
	if err := axclient.EnsureActorEgress(ctx, kubeContext, axNamespace, atespace, allActors, false); err != nil {
		return err
	}

	routerPort, stopPF, err := axclient.StartPortForward(ctx, kubeContext, axclient.ATESystemNamespace, "svc/atenet-router", 443)
	if err != nil {
		return err
	}
	defer stopPF()
	routerAddr := fmt.Sprintf("127.0.0.1:%d", routerPort)

	tlsCfg, notAfter, _, err := axclient.LoadCachedRouterTLS(kubeContext, axNamespace, "ax-server")
	if err != nil {
		return err
	}
	fmt.Printf("  ✔ Loaded router mTLS credentials (valid until %s)\n", notAfter.UTC().Format(time.RFC3339))

	// Phase 1: Elephant drafts DESIGN_SPEC.md in /workspace (contextId="elephant-session-1")
	fmt.Printf("\n==> [EGM Step 2] Elephant Turn 1 (Drafting /workspace/DESIGN_SPEC.md via A2A gRPC SendStreamingMessage)...\n")
	elephantClient, err := axclient.NewActorA2AGRPCClient(ctx, routerAddr, tlsCfg, atespace+"/"+elephantTask)
	if err != nil {
		return err
	}
	defer elephantClient.Destroy()

	card, err := elephantClient.GetExtendedAgentCard(ctx, &a2a.GetExtendedAgentCardRequest{})
	if err != nil {
		return fmt.Errorf("elephant GetExtendedAgentCard: %w", err)
	}
	fmt.Printf("  ✔ Elephant AgentCard : name=%q version=%q\n", card.Name, card.Version)

	draftPrompt := "Read CONTEXT.md in your workspace. Draft a concise (~40-line) design specification for the Webhook Delivery Service into DESIGN_SPEC.md using write_file, and return the full markdown text of DESIGN_SPEC.md in your reply."
	draftText, dur1, err := axclient.SendA2AGRPCMessage(ctx, elephantClient, "elephant-session-1", draftPrompt, true)
	if err != nil {
		return fmt.Errorf("elephant Turn 1 failed: %w", err)
	}
	fmt.Printf("  ✔ Elephant Turn 1 completed in %s (%d chars)\n", dur1.Round(time.Millisecond), len(draftText))
	fmt.Printf("\n--- [Elephant Initial Draft (Turn 1)] ---\n%s\n-----------------------------------------\n", draftText)

	// Phase 2: Invert Elephant residency — suspend Elephant so all 3 gVisor workers are free for the 3 Goldfish reviewers!
	if axBin != "" {
		fmt.Printf("\n==> [EGM Step 3] Suspending %s to free its gVisor worker slot before 3-way parallel Goldfish wave...\n", elephantTask)
		if err := runAX(ctx, axBin, "suspend", "task", elephantTask, "-a", atespace); err != nil {
			return err
		}
	}

	// Phase 3: Parallel 3-Goldfish Review Wave over A2A gRPC SendStreamingMessage with wave-scoped contextId
	fmt.Printf("\n==> [EGM Step 4] Launching 3 stateless Goldfish reviewers in parallel over A2A gRPC SendStreamingMessage...\n")
	type waveResult struct {
		task      string
		contextID string
		duration  time.Duration
		raw       string
		parsed    goldfishReviewOutput
		err       error
	}
	results := make([]waveResult, len(goldfishTasks))
	var wg sync.WaitGroup
	for i, gfTask := range goldfishTasks {
		wg.Add(1)
		go func(idx int, taskName string) {
			defer wg.Done()
			waveCtxID := fmt.Sprintf("wave-1-%s-%d", taskName, time.Now().Unix())
			gfClient, err := axclient.NewActorA2AGRPCClient(ctx, routerAddr, tlsCfg, atespace+"/"+taskName)
			if err != nil {
				results[idx] = waveResult{task: taskName, err: err}
				return
			}
			defer gfClient.Destroy()

			reviewPrompt := fmt.Sprintf(
				"Evaluate the following Webhook Delivery Service design draft using your specialized Goldfish lens and return ONLY a JSON object matching your output schema (reviewer, verdict, summary, findings):\n\n%s",
				draftText,
			)
			rawReply, dur, err := axclient.SendA2AGRPCMessage(ctx, gfClient, waveCtxID, reviewPrompt, true)
			res := waveResult{
				task:      taskName,
				contextID: waveCtxID,
				duration:  dur,
				raw:       rawReply,
				err:       err,
			}
			if err == nil {
				if parseErr := axclient.ExtractJSON(rawReply, &res.parsed); parseErr != nil {
					res.parsed = goldfishReviewOutput{
						Reviewer: taskName,
						Verdict:  "REVIEWED",
						Summary:  rawReply,
					}
				}
			}
			results[idx] = res

			// Immediately suspend each stateless Goldfish back to zero compute!
			if axBin != "" {
				_ = runAX(ctx, axBin, "suspend", "task", taskName, "-a", atespace)
			}
		}(i, gfTask)
	}
	wg.Wait()

	var allFindings []goldfishReviewOutput
	for _, r := range results {
		if r.err != nil {
			return fmt.Errorf("goldfish %s failed: %w", r.task, r.err)
		}
		fmt.Printf("\n  ✔ [%s] (contextId=%s, stream=%s, verdict=%s) -> Suspended\n",
			r.task, r.contextID, r.duration.Round(time.Millisecond), r.parsed.Verdict)
		prettyJSON, _ := json.MarshalIndent(r.parsed, "    ", "  ")
		fmt.Printf("    %s\n", string(prettyJSON))
		allFindings = append(allFindings, r.parsed)
	}

	// Phase 4: Wake the suspended Elephant via A2A gRPC SendStreamingMessage on the SAME contextId ("elephant-session-1")
	findingsJSON, _ := json.MarshalIndent(allFindings, "", "  ")
	fmt.Printf("\n==> [EGM Step 5] Elephant Turn 2 (Wake-on-Request via A2A gRPC SendStreamingMessage, contextId=\"elephant-session-1\")...\n")
	resolvePrompt := fmt.Sprintf(
		"Three stateless Goldfish reviewers audited your Turn 1 DESIGN_SPEC.md draft and returned these structured findings:\n\n%s\n\n"+
			"1. Update DESIGN_SPEC.md using write_file to resolve their blocker/major findings (idempotency keys, retry backoff/DLQ, and quota bounds).\n"+
			"2. Write a short RESOLUTION_LOG.md summarizing how you addressed each Goldfish reviewer's critique.\n"+
			"3. Reply with a 3-bullet summary of the changes and confirm the filename you drafted in Turn 1.",
		string(findingsJSON),
	)
	elephantReply2, dur2, err := axclient.SendA2AGRPCMessage(ctx, elephantClient, "elephant-session-1", resolvePrompt, true)
	if err != nil {
		return fmt.Errorf("elephant Turn 2 failed: %w", err)
	}
	fmt.Printf("  ✔ Elephant Turn 2 (wake + revision) completed in %s\n", dur2.Round(time.Millisecond))
	fmt.Printf("\n--- [Elephant Resolution Summary (Turn 2)] ---\n%s\n----------------------------------------------\n", elephantReply2)
	return nil
}

func runInClusterDelegation(ctx context.Context, kubeContext, axNamespace, atespace string) error {
	leadTask := "lead-engineer"
	specialistTask := "security-specialist"

	fmt.Printf("\n==> [Step 1] Configuring Substrate EgressPolicy for %s (Google APIs + in-cluster atenet-router:443) and %s...\n",
		leadTask, specialistTask)
	if err := axclient.EnsureActorEgress(ctx, kubeContext, axNamespace, atespace, []string{leadTask}, true); err != nil {
		return err
	}
	if err := axclient.EnsureActorEgress(ctx, kubeContext, axNamespace, atespace, []string{specialistTask}, false); err != nil {
		return err
	}

	routerPort, stopPF, err := axclient.StartPortForward(ctx, kubeContext, axclient.ATESystemNamespace, "svc/atenet-router", 443)
	if err != nil {
		return err
	}
	defer stopPF()
	routerAddr := fmt.Sprintf("127.0.0.1:%d", routerPort)

	tlsCfg, notAfter, _, err := axclient.LoadCachedRouterTLS(kubeContext, axNamespace, "ax-server")
	if err != nil {
		return err
	}
	fmt.Printf("  ✔ Router mTLS credentials active (NotAfter=%s)\n", notAfter.UTC().Format(time.RFC3339))

	leadClient, err := axclient.NewActorA2AGRPCClient(ctx, routerAddr, tlsCfg, atespace+"/"+leadTask)
	if err != nil {
		return err
	}
	defer leadClient.Destroy()

	fmt.Printf("\n==> [Step 2] Sending SINGLE A2A gRPC SendStreamingMessage request to %s (while %s is Suspended)...\n",
		leadTask, specialistTask)
	prompt := "1. Read webhook_handler.go in your workspace using read_file.\n" +
		"2. Call your MCP tool `delegate_to_actor` with actor=\"security-specialist\" and pass the contents of webhook_handler.go so the specialist can audit it for HMAC timing attacks and replay vulnerabilities.\n" +
		"3. Apply the security-specialist's recommended fixes to webhook_handler.go using write_file, write a brief summary to DELEGATION_REPORT.md, and reply with the specialist's key findings and your fix."

	reply, dur, err := axclient.SendA2AGRPCMessage(ctx, leadClient, "lead-session-1", prompt, true)
	if err != nil {
		return err
	}
	fmt.Printf("  ✔ Single-turn autonomous in-cluster delegation completed in %s\n", dur.Round(time.Millisecond))
	fmt.Printf("\n--- [%s Reply (via A2A gRPC SendStreamingMessage)] ---\n%s\n------------------------------------------------------------\n",
		leadTask, reply)
	return nil
}

func runAX(ctx context.Context, axBin string, args ...string) error {
	out, err := exec.CommandContext(ctx, axBin, args...).CombinedOutput()
	if err != nil {
		return fmt.Errorf("ax %s: %w (%s)", strings.Join(args, " "), err, strings.TrimSpace(string(out)))
	}
	fmt.Printf("  ✔ %s\n", strings.TrimSpace(string(out)))
	return nil
}

func fatalf(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "error: "+format+"\n", args...)
	os.Exit(1)
}
