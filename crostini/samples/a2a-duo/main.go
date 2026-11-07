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

// Command a2a-duo orchestrates two AX Genkit tasks (coder-agent and
// auditor-agent) running in isolated gVisor sandboxes on Agent Substrate,
// communicating strictly over the A2A gRPC transport (lf.a2a.v1.A2AService)
// routed through atenet-router over mTLS.
package main

import (
	"bufio"
	"context"
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	"github.com/a2aproject/a2a-go/v2/a2a"
	"github.com/a2aproject/a2a-go/v2/a2aclient"
	a2agrpcv1 "github.com/a2aproject/a2a-go/v2/a2agrpc/v1"
	ateapipb "go.ate.dev/substrate/api/ateapi/v1"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/credentials"
	"google.golang.org/grpc/metadata"
	"google.golang.org/grpc/status"
)

const (
	ateSystemNamespace = "ate-system"
	ateAPIAudience     = "api.ate-system.svc"
	routerAuthority    = "atenet-router.ate-system.svc"
)

type cachedRouterTLS struct {
	TrustBundlePEM string    `json:"trust_bundle_pem"`
	CertChainPEM   string    `json:"cert_chain_pem"`
	KeyPEM         string    `json:"key_pem"`
	ExpiresAt      time.Time `json:"expires_at"`
}

func main() {
	var (
		atespace      string
		axNamespace   string
		kubeContext   string
		coderTask     string
		auditorTask   string
		egressOnlyFor string
		axBin         string
	)
	flag.StringVar(&atespace, "atespace", "default", "Atespace for the tasks")
	flag.StringVar(&axNamespace, "ax-namespace", "ax-system", "Namespace where ax-server is deployed")
	flag.StringVar(&kubeContext, "context", "kind-ax-e2e", "Kubernetes context")
	flag.StringVar(&coderTask, "coder", "coder-agent", "Name of the coder Genkit task")
	flag.StringVar(&auditorTask, "auditor", "auditor-agent", "Name of the auditor Genkit task")
	flag.StringVar(&egressOnlyFor, "ensure-egress-only", "", "If set, only ensure Google API egress policy for this comma-separated list of actors and exit")
	flag.StringVar(&axBin, "ax-bin", "", "Path to the ax CLI binary (used to trigger suspend between turns)")
	flag.Parse()

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()

	var actors []string
	if egressOnlyFor != "" {
		for _, a := range strings.Split(egressOnlyFor, ",") {
			if trimmed := strings.TrimSpace(a); trimmed != "" {
				actors = append(actors, trimmed)
			}
		}
	} else {
		actors = []string{coderTask, auditorTask}
	}

	if err := ensureGoogleAPIEgress(ctx, kubeContext, axNamespace, atespace, actors); err != nil {
		fatalf("ensuring actor egress policies: %v", err)
	}
	if egressOnlyFor != "" {
		return
	}

	// Start a port-forward to ate-system/svc/atenet-router:443.
	routerPort, stopPF, err := startPortForward(ctx, kubeContext, ateSystemNamespace, "svc/atenet-router", 443)
	if err != nil {
		fatalf("port-forwarding atenet-router: %v", err)
	}
	defer stopPF()

	tlsCfg, err := loadRouterTLSConfig(kubeContext, axNamespace, "ax-server")
	if err != nil {
		fatalf("loading router mTLS config: %v", err)
	}

	routerAddr := fmt.Sprintf("127.0.0.1:%d", routerPort)
	coderClient, err := newActorA2AGRPCClient(ctx, routerAddr, tlsCfg, atespace+"/"+coderTask)
	if err != nil {
		fatalf("creating coder A2A gRPC client: %v", err)
	}
	defer coderClient.Destroy()

	auditorClient, err := newActorA2AGRPCClient(ctx, routerAddr, tlsCfg, atespace+"/"+auditorTask)
	if err != nil {
		fatalf("creating auditor A2A gRPC client: %v", err)
	}
	defer auditorClient.Destroy()

	// Step 1: Discover both agents via A2A gRPC GetExtendedAgentCard.
	// Note: If either task is Suspended, atenet-router wakes it on demand!
	fmt.Printf("\n==> [Step 1] Discovering AgentCards over A2A gRPC (lf.a2a.v1.A2AService/GetExtendedAgentCard)...\n")
	coderCard, err := coderClient.GetExtendedAgentCard(ctx, &a2a.GetExtendedAgentCardRequest{})
	if err != nil {
		fatalf("coder GetExtendedAgentCard over gRPC: %v", err)
	}
	fmt.Printf("  ✔ Coder AgentCard   : name=%q version=%q protocols=%v\n",
		coderCard.Name, coderCard.Version, formatInterfaces(coderCard.SupportedInterfaces))

	auditorCard, err := auditorClient.GetExtendedAgentCard(ctx, &a2a.GetExtendedAgentCardRequest{})
	if err != nil {
		fatalf("auditor GetExtendedAgentCard over gRPC: %v", err)
	}
	fmt.Printf("  ✔ Auditor AgentCard : name=%q version=%q protocols=%v\n",
		auditorCard.Name, auditorCard.Version, formatInterfaces(auditorCard.SupportedInterfaces))

	// Step 2: Turn 1 — Ask coder-agent over A2A gRPC to inspect /workspace and fix retry_test.go.
	fmt.Printf("\n==> [Step 2] Turn 1 (Orchestrator -> %s via A2A gRPC SendMessage, contextId=\"coder-session-1\")...\n", coderTask)
	turn1Prompt := "Inspect README.md and retry_test.go in your workspace using your filesystem tools. Fix the zero/negative maxJitter panic bug in retry_test.go, and reply with the updated Go code and a 2-sentence explanation."
	coderReply1, err := sendA2AGRPCMessage(ctx, coderClient, "coder-session-1", turn1Prompt)
	if err != nil {
		fatalf("coder Turn 1 SendMessage over gRPC: %v", err)
	}
	fmt.Printf("\n--- [%s Reply (Turn 1 via A2A gRPC)] ---\n%s\n-----------------------------------------\n", coderTask, coderReply1)

	// Step 3: Turn 2 — Send coder-agent's patch to auditor-agent over A2A gRPC for security & edge-case review.
	fmt.Printf("\n==> [Step 3] Turn 2 (%s -> %s via A2A gRPC SendMessage, contextId=\"audit-session-1\")...\n", coderTask, auditorTask)
	auditPrompt := fmt.Sprintf(
		"Review the following patch and explanation produced by coder-agent for payd's retry_test.go:\n\n%s\n\n"+
			"1. Use your filesystem tool `write_file` to save a short audit report to `AUDIT_VERDICT.md` in your workspace.\n"+
			"2. Reply with your verdict (APPROVED or NEEDS_WORK) and ask coder-agent to also add a table-driven test or explicit negative input assertion (`ComputeJitter(-5) == 0`) in `retry_test.go`.",
		coderReply1,
	)
	auditorReply, err := sendA2AGRPCMessage(ctx, auditorClient, "audit-session-1", auditPrompt)
	if err != nil {
		fatalf("auditor Turn 2 SendMessage over gRPC: %v", err)
	}
	fmt.Printf("\n--- [%s Reply (Turn 2 via A2A gRPC)] ---\n%s\n-------------------------------------------\n", auditorTask, auditorReply)

	// Step 4: Suspend coder-agent to checkpoint /workspace/.genkit/snapshots to RustFS and tear down its gVisor sandbox!
	if axBin != "" {
		fmt.Printf("\n==> [Step 4] Suspending %s (`ax suspend task %s`) to test A2A gRPC Wake-on-Request & session persistence...\n", coderTask, coderTask)
		out, err := exec.CommandContext(ctx, axBin, "suspend", "task", coderTask, "-a", atespace).CombinedOutput()
		if err != nil {
			fatalf("suspending %s: %v (%s)", coderTask, err, strings.TrimSpace(string(out)))
		}
		fmt.Printf("  ✔ %s\n", strings.TrimSpace(string(out)))
	}

	// Step 5: Turn 3 — Deliver auditor-agent's review back to the SUSPENDED coder-agent over A2A gRPC!
	// atenet-router automatically wakes coder-agent onto a new gVisor worker, restores /workspace from RustFS,
	// and genkit-runner resumes contextId="coder-session-1" from /workspace/.genkit/snapshots!
	fmt.Printf("\n==> [Step 5] Turn 3 (%s -> %s via A2A gRPC SendMessage, waking %s on-demand, contextId=\"coder-session-1\")...\n",
		auditorTask, coderTask, coderTask)
	turn3Prompt := fmt.Sprintf(
		"The security auditor reviewed your Turn 1 patch and responded:\n\n%s\n\n"+
			"Apply their feedback to `retry_test.go`, write a short `HANDOFF_COMPLETE.md` summarizing both turns, and confirm which file you fixed in Turn 1.",
		auditorReply,
	)
	coderReply2, err := sendA2AGRPCMessage(ctx, coderClient, "coder-session-1", turn3Prompt)
	if err != nil {
		fatalf("coder Turn 3 SendMessage over gRPC: %v", err)
	}
	fmt.Printf("\n--- [%s Reply (Turn 3 via A2A gRPC after Wake-on-Request)] ---\n%s\n--------------------------------------------------------------\n",
		coderTask, coderReply2)
}

func sendA2AGRPCMessage(ctx context.Context, client *a2aclient.Client, contextID, text string) (string, error) {
	var lastErr error
	for attempt := 1; attempt <= 3; attempt++ {
		callCtx, cancel := context.WithTimeout(ctx, 90*time.Second)
		msg := a2a.NewMessage(a2a.MessageRoleUser, a2a.NewTextPart(text))
		msg.ContextID = contextID
		res, err := client.SendMessage(callCtx, &a2a.SendMessageRequest{Message: msg})
		cancel()
		if err != nil {
			lastErr = err
			fmt.Printf("  [retry %d/3] A2A gRPC SendMessage error: %v\n", attempt, err)
			time.Sleep(2 * time.Second)
			continue
		}
		switch v := res.(type) {
		case *a2a.Message:
			var parts []string
			for _, p := range v.Parts {
				if t, ok := p.Content.(a2a.Text); ok {
					parts = append(parts, string(t))
				}
			}
			return strings.Join(parts, "\n"), nil
		case *a2a.Task:
			if v.Status.Message != nil {
				var parts []string
				for _, p := range v.Status.Message.Parts {
					if t, ok := p.Content.(a2a.Text); ok {
						parts = append(parts, string(t))
					}
				}
				return strings.Join(parts, "\n"), nil
			}
			return fmt.Sprintf("(task %s state=%s)", v.ID, v.Status.State), nil
		default:
			return fmt.Sprintf("%#v", res), nil
		}
	}
	return "", lastErr
}

func newActorA2AGRPCClient(ctx context.Context, routerAddr string, tlsCfg *tls.Config, targetActor string) (*a2aclient.Client, error) {
	unaryInterceptor := func(ctx context.Context, method string, req, reply any, cc *grpc.ClientConn, invoker grpc.UnaryInvoker, opts ...grpc.CallOption) error {
		ctx = metadata.AppendToOutgoingContext(ctx, "ate-target-actor", targetActor)
		return invoker(ctx, method, req, reply, cc, opts...)
	}
	streamInterceptor := func(ctx context.Context, desc *grpc.StreamDesc, cc *grpc.ClientConn, method string, streamer grpc.Streamer, opts ...grpc.CallOption) (grpc.ClientStream, error) {
		ctx = metadata.AppendToOutgoingContext(ctx, "ate-target-actor", targetActor)
		return streamer(ctx, desc, cc, method, opts...)
	}

	dialOpts := []grpc.DialOption{
		grpc.WithTransportCredentials(credentials.NewTLS(tlsCfg)),
		grpc.WithAuthority(routerAuthority),
		grpc.WithUnaryInterceptor(unaryInterceptor),
		grpc.WithStreamInterceptor(streamInterceptor),
	}

	return a2aclient.NewFromEndpoints(ctx, []*a2a.AgentInterface{
		a2a.NewAgentInterface(routerAddr, a2a.TransportProtocolGRPC),
	}, a2agrpcv1.WithGRPCTransport(dialOpts...))
}

func formatInterfaces(ifaces []*a2a.AgentInterface) []string {
	var out []string
	for _, iface := range ifaces {
		out = append(out, fmt.Sprintf("%s(%s)", iface.ProtocolBinding, iface.ProtocolVersion))
	}
	return out
}

func loadRouterTLSConfig(kubeContext, namespace, serviceAccount string) (*tls.Config, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return nil, err
	}
	cacheFile := filepath.Join(home, ".ax", "tunnels", fmt.Sprintf("%s-%s-%s-router-tls.json", kubeContext, namespace, serviceAccount))
	data, err := os.ReadFile(cacheFile)
	if err != nil {
		return nil, fmt.Errorf("reading %s (run `ax ssh` once to populate router mTLS cache): %w", cacheFile, err)
	}
	var cached cachedRouterTLS
	if err := json.Unmarshal(data, &cached); err != nil {
		return nil, err
	}
	pool := x509.NewCertPool()
	if !pool.AppendCertsFromPEM([]byte(cached.TrustBundlePEM)) {
		return nil, fmt.Errorf("no valid certs in trust bundle")
	}
	cert, err := tls.X509KeyPair([]byte(cached.CertChainPEM), []byte(cached.KeyPEM))
	if err != nil {
		return nil, err
	}
	return &tls.Config{
		MinVersion:   tls.VersionTLS12,
		RootCAs:      pool,
		Certificates: []tls.Certificate{cert},
		ServerName:   routerAuthority,
	}, nil
}

func ensureGoogleAPIEgress(ctx context.Context, kubeContext, axNamespace, atespace string, actors []string) error {
	apiPort, stopPF, err := startPortForward(ctx, kubeContext, ateSystemNamespace, "svc/api", 443)
	if err != nil {
		return err
	}
	defer stopPF()

	tokenBytes, err := exec.CommandContext(ctx, "kubectl", "--context", kubeContext,
		"create", "token", "ax-server", "-n", axNamespace,
		"--audience="+ateAPIAudience, "--duration=1h").CombinedOutput()
	if err != nil {
		return fmt.Errorf("minting token: %w (%s)", err, strings.TrimSpace(string(tokenBytes)))
	}
	token := strings.TrimSpace(string(tokenBytes))

	conn, err := grpc.NewClient(
		fmt.Sprintf("127.0.0.1:%d", apiPort),
		grpc.WithTransportCredentials(credentials.NewTLS(&tls.Config{
			InsecureSkipVerify: true,
			ServerName:         ateAPIAudience,
		})),
		grpc.WithAuthority(ateAPIAudience),
		grpc.WithUnaryInterceptor(func(ctx context.Context, method string, req, reply any, cc *grpc.ClientConn, invoker grpc.UnaryInvoker, opts ...grpc.CallOption) error {
			ctx = metadata.AppendToOutgoingContext(ctx, "authorization", "Bearer "+token)
			return invoker(ctx, method, req, reply, cc, opts...)
		}),
	)
	if err != nil {
		return err
	}
	defer conn.Close()

	ctrl := ateapipb.NewControlClient(conn)
	policy := &ateapipb.EgressPolicy{
		Metadata: &ateapipb.ResourceMetadata{
			Atespace: atespace,
			Name:     "default",
		},
		Rules: []*ateapipb.EgressRule{{
			TlsPassthrough: &ateapipb.TlsPassthroughRule{
				Hostnames: []string{
					"*.googleapis.com",
					"googleapis.com",
					"*.google.com",
					"accounts.google.com",
				},
				Ports: &ateapipb.Ports{
					Numbers: []int32{443},
				},
			},
		}},
	}

	for _, actor := range actors {
		ref := &ateapipb.ObjectRef{Atespace: atespace, Name: actor}
		_, err := ctrl.CreateActorEgressPolicy(ctx, &ateapipb.CreateActorEgressPolicyRequest{
			Actor:        ref,
			EgressPolicy: policy,
		})
		if err != nil && status.Code(err) == codes.AlreadyExists {
			existing, getErr := ctrl.GetActorEgressPolicy(ctx, &ateapipb.GetActorEgressPolicyRequest{
				Actor: ref,
				Name:  "default",
			})
			if getErr != nil {
				return fmt.Errorf("getting existing egress policy for %s/%s: %w", atespace, actor, getErr)
			}
			_, err = ctrl.UpdateActorEgressPolicy(ctx, &ateapipb.UpdateActorEgressPolicyRequest{
				Actor: ref,
				EgressPolicy: &ateapipb.EgressPolicy{
					Metadata: existing.GetMetadata(),
					Rules:    policy.GetRules(),
				},
			})
		}
		if err != nil {
			return fmt.Errorf("setting egress policy for %s/%s: %w", atespace, actor, err)
		}
		fmt.Printf("  ✔ Configured Substrate EgressPolicy (TlsPassthrough *.googleapis.com:443) for actor %s/%s\n", atespace, actor)
	}
	return nil
}

var portForwardRe = regexp.MustCompile(`Forwarding from 127\.0\.0\.1:(\d+)`)

func startPortForward(ctx context.Context, kubeContext, namespace, target string, remotePort int) (int, func(), error) {
	pfCtx, cancel := context.WithCancel(ctx)
	cmd := exec.CommandContext(pfCtx, "kubectl", "--context", kubeContext,
		"-n", namespace, "port-forward", target, fmt.Sprintf("0:%d", remotePort))
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		cancel()
		return 0, nil, err
	}
	cmd.Stderr = os.Stderr
	if err := cmd.Start(); err != nil {
		cancel()
		return 0, nil, err
	}

	portCh := make(chan int, 1)
	errCh := make(chan error, 1)
	go func() {
		sc := bufio.NewScanner(stdout)
		for sc.Scan() {
			if m := portForwardRe.FindStringSubmatch(sc.Text()); len(m) == 2 {
				var p int
				_, _ = fmt.Sscanf(m[1], "%d", &p)
				portCh <- p
				return
			}
		}
		errCh <- fmt.Errorf("kubectl port-forward exited without reporting local port")
	}()

	select {
	case p := <-portCh:
		stop := func() {
			cancel()
			_ = cmd.Wait()
		}
		return p, stop, nil
	case err := <-errCh:
		cancel()
		_ = cmd.Wait()
		return 0, nil, err
	case <-time.After(15 * time.Second):
		cancel()
		_ = cmd.Wait()
		return 0, nil, fmt.Errorf("timed out waiting for kubectl port-forward to %s/%s", namespace, target)
	}
}

func fatalf(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "error: "+format+"\n", args...)
	os.Exit(1)
}
