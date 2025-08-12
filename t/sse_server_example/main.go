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

package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
	"time"
)

func sseHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")

	f, ok := w.(http.Flusher)
	if !ok {
		http.Error(w, "Streaming unsupported", http.StatusInternalServerError)
		return
	}
	// Initial chunk with assistant role
	initialChunk := `{"id":"chatcmpl-123","object":"chat.completion.chunk","created":1694268190,"model":"gpt-4o-mini","system_fingerprint":"fp_44709d6fcb","choices":[{"index":0,"delta":{"role":"assistant","content":""},"logprobs":null,"finish_reason":null}]}`
	fmt.Fprintf(w, "data: %s\n\n", initialChunk)
	f.Flush()

	// Content chunks with parts of the generated text
	contentParts := []string{
		"Silent circuits hum,\\n",             // First line of haiku
		"Machine mind learns and evolves—\\n", // Second line
		"Dreams of silicon.",                  // Third line
	}

	for _, part := range contentParts {
		contentChunk := fmt.Sprintf(
			`{"id":"chatcmpl-123","object":"chat.completion.chunk","created":1694268190,"model":"gpt-4o-mini","system_fingerprint":"fp_44709d6fcb","choices":[{"index":0,"delta":{"content":"%s"},"logprobs":null,"finish_reason":null}]}`,
			part,
		)
		fmt.Fprintf(w, "data: %s\n\n", contentChunk)

		f.Flush()
		time.Sleep(500 * time.Millisecond) // Simulate processing delay
	}
	// Final chunk indicating completion
	finalChunk := `{"id":"chatcmpl-123","object":"chat.completion.chunk","created":1694268190,"model":"gpt-4o-mini","system_fingerprint":"fp_44709d6fcb","choices":[{"index":0,"delta":{},"logprobs":null,"finish_reason":"stop"}]}`
	fmt.Fprintf(w, "data: %s\n\n", finalChunk)
	f.Flush()
	fmt.Fprintf(w, "data: %s\n\n", "[DONE]")
	f.Flush()
}

func main() {
	// Create a simple route
	http.HandleFunc("/v1/chat/completions", sseHandler)
	port := os.Args[1]
	// Start the server
	log.Println("Starting server on :", port)
	log.Fatal(http.ListenAndServe(":"+port, nil))
}
