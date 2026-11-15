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

// Command ws-tag creates and verifies an immutable Agent Substrate v1.0 Tag
// from a suspended Workspace setup actor and optionally verifies warm
// wake-on-request hydration via ate-local's embedded atenet-router.
package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"

	ateapipb "go.ate.dev/substrate/api/ateapi/v1"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/credentials/insecure"
	"google.golang.org/grpc/status"
)

func main() {
	endpoint := flag.String("endpoint", "127.0.0.1:50051", "Substrate Control / atenet-router endpoint")
	atespace := flag.String("atespace", "default", "Target atespace")
	sourceActor := flag.String("source-actor", "", "Suspended source actor name")
	tagName := flag.String("tag", "", "Tag name to create")
	verifyActor := flag.String("verify-actor", "", "Optional actor name to spawn from SourceTag and wake via atenet-router")
	flag.Parse()

	if *sourceActor == "" || *tagName == "" {
		log.Fatal("-source-actor and -tag are required")
	}

	ctx, cancel := context.WithTimeout(context.Background(), 45*time.Second)
	defer cancel()

	conn, err := grpc.NewClient(*endpoint, grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		log.Fatalf("dial %s: %v", *endpoint, err)
	}
	defer conn.Close()
	ctrl := ateapipb.NewControlClient(conn)

	// Delete existing tag if present so repeated demo runs are idempotent.
	_, _ = ctrl.DeleteTag(ctx, &ateapipb.DeleteTagRequest{
		Tag: &ateapipb.ObjectRef{Atespace: *atespace, Name: *tagName},
	})

	tag, err := ctrl.CreateTag(ctx, &ateapipb.CreateTagRequest{
		Tag: &ateapipb.Tag{
			Metadata:    &ateapipb.ResourceMetadata{Atespace: *atespace, Name: *tagName},
			Scope:       ateapipb.TagScope_TAG_SCOPE_ATESPACE,
			SourceActor: &ateapipb.ObjectRef{Atespace: *atespace, Name: *sourceActor},
		},
	})
	if err != nil && status.Code(err) == codes.AlreadyExists {
		tag, err = ctrl.GetTag(ctx, &ateapipb.GetTagRequest{
			Tag: &ateapipb.ObjectRef{Atespace: *atespace, Name: *tagName},
		})
	}
	if err != nil {
		log.Fatalf("CreateTag(%s): %v", *tagName, err)
	}

	snapState := tag.GetStatus().GetSnapshot().GetDurableSnapshot().GetState()
	if snapState != ateapipb.SnapshotStorageState_SNAPSHOT_STORAGE_STATE_COMPLETED {
		log.Fatalf("Tag %s durable snapshot state = %v, want COMPLETED", *tagName, snapState)
	}

	warmHTTP := 0
	if *verifyActor != "" {
		src, err := ctrl.GetActor(ctx, &ateapipb.GetActorRequest{
			Actor: &ateapipb.ObjectRef{Atespace: *atespace, Name: *sourceActor},
		})
		if err != nil {
			log.Fatalf("GetActor(%s): %v", *sourceActor, err)
		}
		_, _ = ctrl.DeleteActor(ctx, &ateapipb.DeleteActorRequest{
			Actor: &ateapipb.ObjectRef{Atespace: *atespace, Name: *verifyActor},
		})
		_, err = ctrl.CreateActor(ctx, &ateapipb.CreateActorRequest{
			Actor: &ateapipb.Actor{
				Metadata:      &ateapipb.ResourceMetadata{Atespace: *atespace, Name: *verifyActor},
				ActorTemplate: src.GetActorTemplate(),
				SourceTag:     &ateapipb.ObjectRef{Atespace: *atespace, Name: *tagName},
			},
		})
		if err != nil {
			log.Fatalf("CreateActor(%s from tag %s): %v", *verifyActor, *tagName, err)
		}
		defer func() {
			_, _ = ctrl.DeleteActor(context.Background(), &ateapipb.DeleteActorRequest{
				Actor: &ateapipb.ObjectRef{Atespace: *atespace, Name: *verifyActor},
			})
		}()

		req, err := http.NewRequestWithContext(ctx, http.MethodGet, fmt.Sprintf("http://%s/readyz", *endpoint), nil)
		if err != nil {
			log.Fatalf("NewRequest: %v", err)
		}
		req.Header.Set("ate-target-actor", fmt.Sprintf("%s/%s", *atespace, *verifyActor))
		resp, err := (&http.Client{Timeout: 30 * time.Second}).Do(req)
		if err != nil {
			log.Fatalf("warm wake-on-request via atenet-router failed: %v", err)
		}
		warmHTTP = resp.StatusCode
		_ = resp.Body.Close()
		if warmHTTP != http.StatusOK {
			log.Fatalf("warm wake-on-request HTTP %d, want 200", warmHTTP)
		}
	}

	out := map[string]any{
		"tag":              tag.GetMetadata().GetName(),
		"atespace":         tag.GetMetadata().GetAtespace(),
		"template_uid":     tag.GetStatus().GetActorTemplateUid(),
		"snapshot_uuid":    tag.GetStatus().GetSnapshot().GetUuid(),
		"snapshot_state":   snapState.String(),
		"warm_wakeup_http": warmHTTP,
	}
	enc := json.NewEncoder(os.Stdout)
	_ = enc.Encode(out)
}
