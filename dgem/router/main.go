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

// Command dgem-router runs inside an AX Apple container microVM as a System-1
// decision router backed by DiffusionGemma (dgem) and Genkit Go v1.14.0's
// systemonex.SystemOne plugin.
//
// Given an incoming request (-query), it evaluates specialist_router.json.tmpl
// in one forward pass, computes per-option probabilities and normalized
// Hesitation % (H / ln K), and selects either the single winning specialist AX
// Task (when Hesitation < 16% Clear) or the top-2 specialists (when
// Hesitation >= 16% or runner-up probability >= 0.20) for scale-to-zero
// wake-on-route execution.
package main

import (
	"cmp"
	"context"
	"encoding/json"
	"flag"
	"log"
	"math"
	"os"
	"slices"

	"github.com/GoogleCloudPlatform/dgem/examples/dgemgenkit"
	"github.com/firebase/genkit/go/genkit"
)

const (
	hesitationGate      = 0.16
	runnerUpProbTrigger = 0.20
)

var specialistTaskMap = map[string]string{
	"billing_ops":  "specialist-billing",
	"sec_incident": "specialist-security",
	"code_triage":  "specialist-engineering",
}

// RouteDecision is the structured JSON output emitted by dgem-router.
type RouteDecision struct {
	TargetEndpoint  string             `json:"target_endpoint"`
	Model           string             `json:"model"`
	Query           string             `json:"query"`
	Specialist      string             `json:"specialist"`
	Confidence      float64            `json:"confidence"`
	Hesitation      float64            `json:"hesitation"`
	Band            string             `json:"band"`
	CrossDomain     string             `json:"cross_domain"`
	CrossDomainProb float64            `json:"cross_domain_prob"`
	Urgent          string             `json:"urgent"`
	UrgentProb      float64            `json:"urgent_prob"`
	Severity        string             `json:"severity"`
	SeverityScore   float64            `json:"severity_score"`
	WallTimeMs      int64              `json:"wall_ms"`
	Probabilities   map[string]float64 `json:"probabilities"`
	Targets         []string           `json:"targets"`
}

type optionProb struct {
	Option string
	Prob   float64
}

func main() {
	dgemCfg := dgemgenkit.EndpointConfigFromEnv()
	dgemgenkit.BindEndpointFlags(flag.CommandLine, &dgemCfg)
	tmplPath := flag.String("template", "/opt/dgem/templates/specialist_router.json.tmpl", "Path to specialist_router.json.tmpl")
	query := flag.String("query", "", "Incoming user question or incident description to route")
	flag.Parse()

	if *query == "" {
		log.Fatal("-query is required")
	}

	ctx := context.Background()
	dgemPlugin, closeAdapter := dgemgenkit.NewSystemOnePlugin(dgemCfg)
	defer closeAdapter()

	g := genkit.Init(ctx, genkit.WithPlugins(dgemPlugin))
	dec, err := dgemgenkit.DecideWithTemplate(ctx, g, dgemCfg.GenkitModelName(), *tmplPath, map[string]any{
		"query":   *query,
		"samples": 1,
	})
	if err != nil {
		log.Fatalf("dgem routing decision failed: %v", err)
	}

	specAns, ok := dec.Answers["specialist"]
	if !ok || specAns.Choice == "" {
		log.Fatalf("template %s did not return a valid 'specialist' choice slot", *tmplPath)
	}
	crossAns := dec.Answers["cross_domain"]
	urgAns := dec.Answers["urgent"]
	sevAns := dec.Answers["severity"]

	hes := dec.Hesitation("specialist")
	band := "Clear"
	if hes >= 0.50 {
		band = "Very unsure"
	} else if hes >= hesitationGate {
		band = "Unsure"
	}

	crossLabel := "no"
	if crossAns.Probability >= 0.5 {
		crossLabel = "yes"
	}

	urgLabel := "no"
	if urgAns.Probability >= 0.5 {
		urgLabel = "yes"
	}

	sevLevels := []string{"low", "medium", "high", "critical"}
	sevIdx := int(math.Round(sevAns.Score))
	if sevIdx < 0 {
		sevIdx = 0
	}
	if sevIdx >= len(sevLevels) {
		sevIdx = len(sevLevels) - 1
	}

	var ranked []optionProb
	for k, p := range specAns.Probabilities {
		ranked = append(ranked, optionProb{Option: k, Prob: p})
	}
	slices.SortFunc(ranked, func(a, b optionProb) int {
		return cmp.Compare(b.Prob, a.Prob)
	})

	var targets []string
	if len(ranked) > 0 {
		if t, ok := specialistTaskMap[ranked[0].Option]; ok {
			targets = append(targets, t)
		}
	}
	if len(ranked) > 1 && (hes >= hesitationGate || crossLabel == "yes" || ranked[1].Prob >= runnerUpProbTrigger) {
		if t, ok := specialistTaskMap[ranked[1].Option]; ok {
			targets = append(targets, t)
		}
	}
	if len(targets) == 0 {
		log.Fatalf("no AX target task mapped for specialist choice %q", specAns.Choice)
	}

	out := RouteDecision{
		TargetEndpoint:  dgemCfg.DescribeTarget(),
		Model:           dgemCfg.GenkitModelName(),
		Query:           *query,
		Specialist:      specAns.Choice,
		Confidence:      specAns.Confidence,
		Hesitation:      hes,
		Band:            band,
		CrossDomain:     crossLabel,
		CrossDomainProb: crossAns.Probability,
		Urgent:          urgLabel,
		UrgentProb:      urgAns.Probability,
		Severity:        sevLevels[sevIdx],
		SeverityScore:   sevAns.Score,
		WallTimeMs:      dec.WallTimeMs,
		Probabilities:   specAns.Probabilities,
		Targets:         targets,
	}

	enc := json.NewEncoder(os.Stdout)
	enc.SetIndent("", "  ")
	if err := enc.Encode(out); err != nil {
		log.Fatalf("encode JSON: %v", err)
	}
}
