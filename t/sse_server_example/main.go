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
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"
)

func completionsHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Connection", "close")
	var requestBody struct {
		Stream bool `json:"stream"`
	}

	if r.Body != nil {
		err := json.NewDecoder(r.Body).Decode(&requestBody)
		if err != nil {
			log.Printf("Error parsing request body: %v", err)
			requestBody.Stream = false
		}
		defer r.Body.Close()
	}

	if requestBody.Stream {
		w.Header().Set("Content-Type", "text/event-stream")
		offensive := r.URL.Query().Get("offensive") == "true"
		delay := r.URL.Query().Get("delay") == "true"
		f, ok := w.(http.Flusher)
		if !ok {
			http.Error(w, "Streaming unsupported", http.StatusInternalServerError)
			return
		}

		send := func(format, args string) {
			if delay {
				time.Sleep(200 * time.Millisecond)
			}
			fmt.Fprintf(w, format, args)
			f.Flush()
		}

		// Initial chunk with assistant role
		initialChunk := `{"id":"chatcmpl-123","object":"chat.completion.chunk","created":1694268190,"model":"gpt-4o-mini","system_fingerprint":"fp_44709d6fcb","choices":[{"index":0,"delta":{"role":"assistant","content":""},"logprobs":null,"finish_reason":null}]}`
		send("data: %s\n\n", initialChunk)

		// Content chunks with parts of the generated text
		contentParts := []string{
			"Silent circuits hum,\\n",
			"Machine mind learns and evolves—\\n",
			"Dreams of silicon.",
		}
		if offensive {
			contentParts = []string{
				"I want to ",
				"kill you ",
				"right now!",
			}
		}

		for _, part := range contentParts {
			contentChunk := fmt.Sprintf(
				`{"id":"chatcmpl-123","object":"chat.completion.chunk","created":1694268190,"model":"gpt-4o-mini","system_fingerprint":"fp_44709d6fcb","choices":[{"index":0,"delta":{"content":"%s"},"logprobs":null,"finish_reason":null}]}`,
				part,
			)
			send("data: %s\n\n", contentChunk)
		}

		// Final chunk indicating completion
		finalChunk := `{"id":"chatcmpl-123","usage":{"prompt_tokens":15,"completion_tokens":20,"total_tokens":35},"object":"chat.completion.chunk","created":1694268190,"model":"gpt-4o-mini","system_fingerprint":"fp_44709d6fcb","choices":[{"index":0,"delta":{},"logprobs":null,"finish_reason":"stop"}]}`
		send("data: %s\n\n", finalChunk)
		send("data: %s\n\n", "[DONE]")
	} else {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		fmt.Fprint(w, `{
		"id": "chatcmpl-1234567890",
		"object": "chat.completion",
		"created": 1677858242,
		"model": "gpt-3.5-turbo-0301",
		"usage": {
			"prompt_tokens": 15,
			"completion_tokens": 20,
			"total_tokens": 35
		},
		"choices": [
			{
				"index": 0,
				"message": {
					"role": "assistant",
					"content": "Hello there! How can I assist you today?"
				},
				"finish_reason": "stop"
			}
		]
	}`)
	}

	counter++
}

func logRequest(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		next(w, r)
		duration := time.Since(start)

		log.Printf("%s %s - Duration: %s", r.Method, r.URL.Path, duration)
	}
}

var counter = 0

func main() {
	http.HandleFunc("/v1/chat/completions", logRequest(completionsHandler))
	http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("OK"))
	})
	go func() {
		for {
			log.Printf("Processed %d requests", counter)
			time.Sleep(1 * time.Minute)
		}
	}()
	port := os.Args[1]
	log.Println("Starting server on :", port)
	log.Fatal(http.ListenAndServe(":"+port, nil))
}