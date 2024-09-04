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
