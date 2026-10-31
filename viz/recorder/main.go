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

// Command recorder collects swarm execution traces from AX Valkey pub/sub,
// ax-controller slog output, and recipe orchestrator markers, outputting
// a unified, timestamp-sorted JSON Lines trace file for visualization.
package main

import (
	"bufio"
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log"
	"os"
	"os/signal"
	"sort"
	"strings"
	"sync"
	"syscall"
	"time"

	goredis "github.com/redis/go-redis/v9"
)

type Event struct {
	T        float64        `json:"t"`
	Src      string         `json:"src"`
	Kind     string         `json:"kind"`
	ID       string         `json:"id,omitempty"`
	From     string         `json:"from,omitempty"`
	To       string         `json:"to,omitempty"`
	Phase    string         `json:"phase,omitempty"`
	WorkerIP string         `json:"workerIP,omitempty"`
	Role     string         `json:"role,omitempty"`
	Label    string         `json:"label,omitempty"`
	Meta     map[string]any `json:"meta,omitempty"`
}

type TaskState struct {
	Phase    string
	WorkerIP string
	Ready    bool
}

func nowSeconds() float64 {
	return float64(time.Now().UnixNano()) / 1e9
}

func main() {
	redisAddr := flag.String("redis", "127.0.0.1:6379", "Valkey/Redis server address")
	serverLog := flag.String("server-log", "", "Path to ax-server.log (optional)")
	controllerLog := flag.String("controller-log", "", "Legacy alias for server-log (optional)")
	recipePipe := flag.String("recipe-events", "/tmp/ax-recipe-events.jsonl", "Path to recipe events file or FIFO")
	outFile := flag.String("out", "trace.jsonl", "Path to output trace.jsonl file")
	flag.Parse()

	reconcileLogPath := *serverLog
	if reconcileLogPath == "" {
		reconcileLogPath = *controllerLog
	}

	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()

	var mu sync.Mutex
	var events []*Event

	addEvent := func(e *Event) {
		mu.Lock()
		defer mu.Unlock()
		if e.T == 0 {
			e.T = nowSeconds()
		}
		events = append(events, e)
	}

	// 1. Listen to Valkey pub/sub for task state transitions
	rClient := goredis.NewClient(&goredis.Options{
		Addr: *redisAddr,
	})
	defer rClient.Close()

	go func() {
		pubsub := rClient.PSubscribe(ctx, "*:pubsub:task:*")
		defer pubsub.Close()

		tasks := make(map[string]*TaskState)

		ch := pubsub.Channel()
		for msg := range ch {
			var raw map[string]any
			if err := json.Unmarshal([]byte(msg.Payload), &raw); err != nil {
				continue
			}

			meta, _ := raw["metadata"].(map[string]any)
			taskName, _ := meta["name"].(string)
			if taskName == "" {
				continue
			}

			status, _ := raw["status"].(map[string]any)
			phase, _ := status["phase"].(string)
			workerIP, _ := status["workerIP"].(string)

			var isReady bool
			if conds, ok := status["conditions"].([]any); ok {
				for _, c := range conds {
					if cm, ok := c.(map[string]any); ok {
						if cm["type"] == "Ready" && cm["status"] == "True" {
							isReady = true
						}
					}
				}
			}

			mu.Lock()
			prev, seen := tasks[taskName]
			if !seen {
				prev = &TaskState{}
				tasks[taskName] = prev
			}

			phaseChanged := prev.Phase != phase && phase != ""
			readyChanged := !prev.Ready && isReady
			ipChanged := prev.WorkerIP != workerIP && workerIP != ""

			prev.Phase = phase
			prev.WorkerIP = workerIP
			prev.Ready = isReady
			mu.Unlock()

			now := nowSeconds()
			if phaseChanged {
				addEvent(&Event{
					T:        now,
					Src:      "ax",
					Kind:     "node.phase",
					ID:       taskName,
					Phase:    phase,
					WorkerIP: workerIP,
					Label:    fmt.Sprintf("%s -> %s", taskName, phase),
				})
			}
			if readyChanged || (ipChanged && isReady) {
				addEvent(&Event{
					T:        now,
					Src:      "ax",
					Kind:     "node.ready",
					ID:       taskName,
					Phase:    phase,
					WorkerIP: workerIP,
					Label:    fmt.Sprintf("%s Ready at %s", taskName, workerIP),
				})
			}
		}
	}()

	// 2. Tail reconciler log (ax-server.log) if provided
	if reconcileLogPath != "" {
		go func() {
			f, err := os.Open(reconcileLogPath)
			if err != nil {
				return
			}
			defer f.Close()
			_, _ = f.Seek(0, io.SeekEnd) // start at current end

			reader := bufio.NewReader(f)
			for {
				select {
				case <-ctx.Done():
					return
				default:
				}

				line, err := reader.ReadString('\n')
				if err != nil {
					time.Sleep(100 * time.Millisecond)
					continue
				}

				line = strings.TrimSpace(line)
				if strings.Contains(line, `msg="reconciling task"`) {
					task := extractSlogField(line, "name")
					addEvent(&Event{
						T:     nowSeconds(),
						Src:   "controller",
						Kind:  "ctl.step",
						ID:    "control-plane",
						To:    task,
						Label: fmt.Sprintf("Reconciling %s", task),
					})
				} else if strings.Contains(line, `msg="resuming actor on Substrate worker"`) {
					actor := extractSlogField(line, "actor")
					addEvent(&Event{
						T:     nowSeconds(),
						Src:   "controller",
						Kind:  "ctl.step",
						ID:    "control-plane",
						To:    actor,
						Label: fmt.Sprintf("Resuming actor %s", actor),
					})
				} else if strings.Contains(line, `msg="task successfully resumed"`) || strings.Contains(line, `msg="task successfully reconciled and running"`) {
					task := extractSlogField(line, "name")
					workerIP := extractSlogField(line, "workerIP")
					now := nowSeconds()
					addEvent(&Event{
						T:        now,
						Src:      "ax",
						Kind:     "node.phase",
						ID:       task,
						Phase:    "Running",
						WorkerIP: workerIP,
						Label:    fmt.Sprintf("%s -> Running", task),
					})
					addEvent(&Event{
						T:        now,
						Src:      "ax",
						Kind:     "node.ready",
						ID:       task,
						Phase:    "Running",
						WorkerIP: workerIP,
						Label:    fmt.Sprintf("%s Ready at %s", task, workerIP),
					})
				} else if strings.Contains(line, `msg="suspending actor on Substrate"`) {
					actor := extractSlogField(line, "actor")
					addEvent(&Event{
						T:     nowSeconds(),
						Src:   "controller",
						Kind:  "ctl.step",
						ID:    "control-plane",
						To:    actor,
						Label: fmt.Sprintf("Suspending actor %s", actor),
					})
				} else if strings.Contains(line, `msg="task successfully suspended"`) {
					task := extractSlogField(line, "name")
					addEvent(&Event{
						T:     nowSeconds(),
						Src:   "ax",
						Kind:  "node.phase",
						ID:    task,
						Phase: "Suspended",
						Label: fmt.Sprintf("%s -> Suspended", task),
					})
				} else if strings.Contains(line, `msg="deleting Substrate actor for task"`) {
					task := extractSlogField(line, "task")
					addEvent(&Event{
						T:     nowSeconds(),
						Src:   "controller",
						Kind:  "node.remove",
						ID:    task,
						Label: fmt.Sprintf("Deleted %s", task),
					})
				}
			}
		}()
	}

	// 3. Tail recipe event stream
	doneReadingRecipe := make(chan bool, 1)
	go func() {
		// Wait for recipe pipe to exist
		for {
			select {
			case <-ctx.Done():
				return
			default:
			}
			if _, err := os.Stat(*recipePipe); err == nil {
				break
			}
			time.Sleep(100 * time.Millisecond)
		}

		f, err := os.Open(*recipePipe)
		if err != nil {
			return
		}
		defer f.Close()

		reader := bufio.NewReader(f)
		for {
			select {
			case <-ctx.Done():
				return
			default:
			}

			line, err := reader.ReadString('\n')
			if err != nil {
				time.Sleep(50 * time.Millisecond)
				continue
			}

			line = strings.TrimSpace(line)
			if line == "" {
				continue
			}

			var e Event
			if err := json.Unmarshal([]byte(line), &e); err == nil {
				addEvent(&e)
				if e.Kind == "run.end" {
					doneReadingRecipe <- true
					return
				}
			}
		}
	}()

	fmt.Printf("ax-trace recorder listening on Valkey (%s)... Output: %s\n", *redisAddr, *outFile)

	select {
	case <-ctx.Done():
		fmt.Println("\nSignal received, finalizing trace...")
	case <-doneReadingRecipe:
		fmt.Println("\nReceived run.end marker, finalizing trace...")
	}

	// Give pub/sub and logs 500ms to flush final deletes
	time.Sleep(500 * time.Millisecond)

	mu.Lock()
	defer mu.Unlock()

	// Sort events chronologically
	sort.Slice(events, func(i, j int) bool {
		return events[i].T < events[j].T
	})

	// Normalize timestamps relative to first event
	if len(events) > 0 {
		tZero := events[0].T
		for _, e := range events {
			e.T = float64(int((e.T-tZero)*1000)) / 1000.0 // ms precision
		}
	}

	outF, err := os.Create(*outFile)
	if err != nil {
		log.Fatalf("Failed to create output file: %v", err)
	}
	defer outF.Close()

	for _, e := range events {
		data, err := json.Marshal(e)
		if err == nil {
			_, _ = outF.Write(append(data, '\n'))
		}
	}

	fmt.Printf("Trace finalized with %d events -> %s\n", len(events), *outFile)
}

func extractSlogField(line, field string) string {
	needle := field + "="
	idx := strings.Index(line, needle)
	if idx == -1 {
		return ""
	}
	sub := line[idx+len(needle):]
	end := strings.IndexAny(sub, " \t\r\n")
	if end == -1 {
		return strings.Trim(sub, `"`)
	}
	return strings.Trim(sub[:end], `"`)
}
