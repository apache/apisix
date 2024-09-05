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
	// Set the headers for SSE
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")

	// A simple loop that sends a message every 2 seconds
	for i := 0; i < 5; i++ {
		// Create a message to send to the client
		fmt.Fprintf(w, "data: %s\n\n", time.Now().Format(time.RFC3339))

		// Flush the data immediately to the client
		if f, ok := w.(http.Flusher); ok {
			f.Flush()
		} else {
			log.Println("Unable to flush data to client.")
			break
		}

		time.Sleep(500 * time.Millisecond)
	}
	fmt.Fprintf(w, "data: %s\n\n", "[DONE]")
}

func main() {
	// Create a simple route
	http.HandleFunc("/v1/chat/completions", sseHandler)
	port := os.Args[1]
	// Start the server
	log.Println("Starting server on :", port)
	log.Fatal(http.ListenAndServe(":" + port, nil))
}
