/*
 * Licensed to the Apache Software Foundation (ASF) under one or more
 * contributor license agreements.  See the NOTICE file distributed with
 * this work for additional information regarding copyright ownership.
 * The ASF licenses this file to You under the Apache License, Version 2.0
 * (the "License"); you may not use this file except in compliance with
 * the License.  You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package delayetcd

import (
	"testing"

	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
)

func TestGetEtcdDelayChaosUsesInlineDelaySpec(t *testing.T) {
	chaos := getEtcdDelayChaos(30)

	latency, ok, err := unstructured.NestedString(chaos.Object, "spec", "delay", "latency")
	if err != nil || !ok {
		t.Fatalf("expected inline delay latency field, ok=%v err=%v", ok, err)
	}
	if latency != "30ms" {
		t.Fatalf("unexpected latency: got %q, want %q", latency, "30ms")
	}

	if _, ok, _ := unstructured.NestedMap(chaos.Object, "spec", "tcParameter"); ok {
		t.Fatal("unexpected nested tcParameter field")
	}
}
