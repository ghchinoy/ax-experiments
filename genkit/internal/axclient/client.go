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

// Package axclient provides shared helpers for configuring Agent Substrate
// EgressPolicy rules, loading atenet-router mTLS credentials, and invoking AX
// Genkit tasks over the A2A gRPC transport (lf.a2a.v1.A2AService).
package axclient

import (
	"bufio"
	"context"
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
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
	ATESystemNamespace = "ate-system"
	ATEAPIAudience     = "api.ate-system.svc"
	RouterAuthority    = "atenet-router.ate-system.svc"
	InClusterRouterURL = "atenet-router.ate-system.svc.cluster.local:443"
)

type cachedRouterTLS struct {
	TrustBundlePEM string    `json:"trust_bundle_pem"`
	CertChainPEM   string    `json:"cert_chain_pem"`
	KeyPEM         string    `json:"key_pem"`
	ExpiresAt      time.Time `json:"expires_at"`
}

// RouterTLSCachePath returns the path where `ax ssh` caches the router mTLS
// credentials on the host.
func RouterTLSCachePath(kubeContext, namespace, serviceAccount string) (string, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(home, ".ax", "tunnels", fmt.Sprintf("%s-%s-%s-router-tls.json", kubeContext, namespace, serviceAccount)), nil
}

// LoadRouterTLSFromFile parses a cached router TLS JSON file (either on the
// host or mounted inside a sandbox at /workspace/.ax-router-tls.json) and
// returns the *tls.Config along with the leaf certificate's NotAfter timestamp.
func LoadRouterTLSFromFile(path string) (*tls.Config, time.Time, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, time.Time{}, fmt.Errorf("reading router TLS file %s: %w", path, err)
	}
	var cached cachedRouterTLS
	if err := json.Unmarshal(data, &cached); err != nil {
		return nil, time.Time{}, fmt.Errorf("decoding router TLS file %s: %w", path, err)
	}
	pool := x509.NewCertPool()
	if !pool.AppendCertsFromPEM([]byte(cached.TrustBundlePEM)) {
		return nil, time.Time{}, fmt.Errorf("no valid certificates in trust bundle from %s", path)
	}
	cert, err := tls.X509KeyPair([]byte(cached.CertChainPEM), []byte(cached.KeyPEM))
	if err != nil {
		return nil, time.Time{}, fmt.Errorf("parsing router client keypair: %w", err)
	}
	var notAfter time.Time
	if len(cert.Certificate) > 0 {
		if leaf, err := x509.ParseCertificate(cert.Certificate[0]); err == nil {
			notAfter = leaf.NotAfter
		}
	}
	if !notAfter.IsZero() && time.Now().After(notAfter) {
		return nil, notAfter, fmt.Errorf("router mTLS client certificate in %s expired at %s", path, notAfter.UTC().Format(time.RFC3339))
	}
	return &tls.Config{
		MinVersion:   tls.VersionTLS12,
		RootCAs:      pool,
		Certificates: []tls.Certificate{cert},
		ServerName:   RouterAuthority,
	}, notAfter, nil
}

// LoadCachedRouterTLS loads the host's cached router mTLS credentials.
func LoadCachedRouterTLS(kubeContext, namespace, serviceAccount string) (*tls.Config, time.Time, string, error) {
	p, err := RouterTLSCachePath(kubeContext, namespace, serviceAccount)
	if err != nil {
		return nil, time.Time{}, "", err
	}
	cfg, notAfter, err := LoadRouterTLSFromFile(p)
	return cfg, notAfter, p, err
}

// NewActorA2AGRPCClient creates an A2A gRPC client (lf.a2a.v1.A2AService)
// routed through atenet-router over mTLS with `ate-target-actor: <targetActor>`.
func NewActorA2AGRPCClient(ctx context.Context, routerAddr string, tlsCfg *tls.Config, targetActor string) (*a2aclient.Client, error) {
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
		grpc.WithAuthority(RouterAuthority),
		grpc.WithUnaryInterceptor(unaryInterceptor),
		grpc.WithStreamInterceptor(streamInterceptor),
	}

	return a2aclient.NewFromEndpoints(ctx, []*a2a.AgentInterface{
		a2a.NewAgentInterface(routerAddr, a2a.TransportProtocolGRPC),
	}, a2agrpcv1.WithGRPCTransport(dialOpts...))
}

// SendA2AGRPCMessage sends an A2A message over gRPC (using either
// SendStreamingMessage or unary SendMessage) with automatic transient retry and
// returns the agent's text response and elapsed call duration.
func SendA2AGRPCMessage(ctx context.Context, client *a2aclient.Client, contextID, text string, useStreaming bool) (string, time.Duration, error) {
	var lastErr error
	for attempt := 1; attempt <= 3; attempt++ {
		start := time.Now()
		callCtx, cancel := context.WithTimeout(ctx, 90*time.Second)
		msg := a2a.NewMessage(a2a.MessageRoleUser, a2a.NewTextPart(text))
		if contextID != "" {
			msg.ContextID = contextID
		}
		req := &a2a.SendMessageRequest{Message: msg}

		var (
			reply string
			err   error
		)
		if useStreaming {
			reply, err = collectStreamingMessage(callCtx, client, req)
		} else {
			var res a2a.SendMessageResult
			res, err = client.SendMessage(callCtx, req)
			if err == nil {
				reply = formatEvent(res)
			}
		}
		cancel()
		elapsed := time.Since(start)
		if err == nil {
			return reply, elapsed, nil
		}
		lastErr = err
		time.Sleep(2 * time.Second)
	}
	return "", 0, lastErr
}

func collectStreamingMessage(ctx context.Context, client *a2aclient.Client, req *a2a.SendMessageRequest) (string, error) {
	var chunks []string
	for event, err := range client.SendStreamingMessage(ctx, req) {
		if err != nil {
			return "", err
		}
		if text := formatEvent(event); text != "" {
			chunks = append(chunks, text)
		}
	}
	return strings.Join(chunks, "\n"), nil
}

func formatEvent(ev any) string {
	switch v := ev.(type) {
	case *a2a.Message:
		var parts []string
		for _, p := range v.Parts {
			if t, ok := p.Content.(a2a.Text); ok {
				parts = append(parts, string(t))
			}
		}
		return strings.Join(parts, "\n")
	case *a2a.Task:
		if v.Status.Message != nil {
			return formatEvent(v.Status.Message)
		}
		return ""
	case *a2a.TaskStatusUpdateEvent:
		if v.Status.Message != nil {
			return formatEvent(v.Status.Message)
		}
		return ""
	default:
		return ""
	}
}

// ExtractJSON strips optional Markdown code fences (```json ... ```) from an
// agent's text response and unmarshals the JSON payload into out.
func ExtractJSON(raw string, out any) error {
	trimmed := strings.TrimSpace(raw)
	if strings.HasPrefix(trimmed, "```") {
		if idx := strings.Index(trimmed, "\n"); idx != -1 {
			trimmed = trimmed[idx+1:]
		}
		if last := strings.LastIndex(trimmed, "```"); last != -1 {
			trimmed = trimmed[:last]
		}
		trimmed = strings.TrimSpace(trimmed)
	}
	if start := strings.Index(trimmed, "{"); start != -1 {
		if end := strings.LastIndex(trimmed, "}"); end > start {
			trimmed = trimmed[start : end+1]
		}
	}
	return json.Unmarshal([]byte(trimmed), out)
}

// EgressOptions configures optional additional TLS and HTTP hostnames on an
// actor's Substrate EgressPolicy.
type EgressOptions struct {
	IncludeRouter  bool
	IncludeGitHub  bool
	IncludeDGem    bool
	ExtraTLSHosts  []string
	ExtraHTTPHosts []string
	HTTPPorts      []int32
}

// EnsureActorEgress configures the Substrate "default" EgressPolicy on each
// actor in actors to allow TlsPassthrough on port 443 to Google APIs, and
// optionally to in-cluster atenet-router when includeRouter is true.
func EnsureActorEgress(ctx context.Context, kubeContext, axNamespace, atespace string, actors []string, includeRouter bool) error {
	return EnsureActorEgressWithOptions(ctx, kubeContext, axNamespace, atespace, actors, EgressOptions{
		IncludeRouter: includeRouter,
	})
}

// EnsureActorEgressWithOptions configures the Substrate "default" EgressPolicy
// on each actor in actors with the specified TLS passthrough (port 443) and
// cleartext HTTP rules.
func EnsureActorEgressWithOptions(ctx context.Context, kubeContext, axNamespace, atespace string, actors []string, opts EgressOptions) error {
	apiPort, stopPF, err := StartPortForward(ctx, kubeContext, ATESystemNamespace, "svc/api", 443)
	if err != nil {
		return err
	}
	defer stopPF()

	tokenBytes, err := exec.CommandContext(ctx, "kubectl", "--context", kubeContext,
		"create", "token", "ax-server", "-n", axNamespace,
		"--audience="+ATEAPIAudience, "--duration=1h").CombinedOutput()
	if err != nil {
		return fmt.Errorf("minting token: %w (%s)", err, strings.TrimSpace(string(tokenBytes)))
	}
	token := strings.TrimSpace(string(tokenBytes))

	conn, err := grpc.NewClient(
		fmt.Sprintf("127.0.0.1:%d", apiPort),
		grpc.WithTransportCredentials(credentials.NewTLS(&tls.Config{
			InsecureSkipVerify: true,
			ServerName:         ATEAPIAudience,
		})),
		grpc.WithAuthority(ATEAPIAudience),
		grpc.WithUnaryInterceptor(func(ctx context.Context, method string, req, reply any, cc *grpc.ClientConn, invoker grpc.UnaryInvoker, opts ...grpc.CallOption) error {
			ctx = metadata.AppendToOutgoingContext(ctx, "authorization", "Bearer "+token)
			return invoker(ctx, method, req, reply, cc, opts...)
		}),
	)
	if err != nil {
		return err
	}
	defer conn.Close()

	hosts := []string{
		"*.googleapis.com",
		"googleapis.com",
		"*.google.com",
		"accounts.google.com",
	}
	if opts.IncludeRouter {
		hosts = append(hosts,
			"atenet-router.ate-system.svc",
			"atenet-router.ate-system.svc.cluster.local",
		)
	}
	if opts.IncludeGitHub {
		hosts = append(hosts,
			"github.com",
			"*.githubusercontent.com",
			"pypi.org",
			"files.pythonhosted.org",
		)
	}
	if opts.IncludeDGem {
		hosts = append(hosts, "*.a.run.app")
	}
	hosts = append(hosts, opts.ExtraTLSHosts...)

	ctrl := ateapipb.NewControlClient(conn)
	rules := []*ateapipb.EgressRule{{
		TlsPassthrough: &ateapipb.TlsPassthroughRule{
			Hostnames: hosts,
			Ports: &ateapipb.Ports{
				Numbers: []int32{443},
			},
		},
	}}

	httpHosts := append([]string(nil), opts.ExtraHTTPHosts...)
	if opts.IncludeDGem {
		httpHosts = append(httpHosts,
			"host.docker.internal",
			"host.containers.internal",
			"dgem-gateway.default.svc.cluster.local",
			"dgem-gateway.default.svc",
		)
	}
	if len(httpHosts) > 0 {
		ports := opts.HTTPPorts
		if len(ports) == 0 {
			ports = []int32{8095, 8080, 80}
		}
		rules = append(rules, &ateapipb.EgressRule{
			Http: &ateapipb.HttpRule{
				Hostnames: httpHosts,
				Ports: &ateapipb.Ports{
					Numbers: ports,
				},
			},
		})
	}

	for _, actor := range actors {
		ref := &ateapipb.ObjectRef{Atespace: atespace, Name: actor}
		_, err := ctrl.CreateActorEgressPolicy(ctx, &ateapipb.CreateActorEgressPolicyRequest{
			Actor: ref,
			EgressPolicy: &ateapipb.EgressPolicy{
				Metadata: &ateapipb.ResourceMetadata{
					Atespace: atespace,
					Name:     "default",
				},
				Rules: rules,
			},
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
					Rules:    rules,
				},
			})
		}
		if err != nil {
			return fmt.Errorf("setting egress policy for %s/%s: %w", atespace, actor, err)
		}
		fmt.Printf("  ✔ Configured Substrate EgressPolicy (hosts=%v) for actor %s/%s\n", hosts, atespace, actor)
	}
	return nil
}

var portForwardRe = regexp.MustCompile(`Forwarding from 127\.0\.0\.1:(\d+)`)

// StartPortForward starts `kubectl port-forward` on an ephemeral local port and
// returns the bound local port and a cleanup function.
func StartPortForward(ctx context.Context, kubeContext, namespace, target string, remotePort int) (int, func(), error) {
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
