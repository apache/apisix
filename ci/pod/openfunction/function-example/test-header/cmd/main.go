package main

import (
	"log"
	"net/http"

	hello "example.com/hello"
)

func main() {
	http.HandleFunc("/", hello.HelloWorld)
	log.Fatal(http.ListenAndServe(":8080", nil))
}
