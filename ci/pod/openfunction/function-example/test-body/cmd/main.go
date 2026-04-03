package main

import (
	"context"
	"log"

	_ "example.com/hello"
	"github.com/OpenFunction/functions-framework-go/framework"
)

func main() {
	fwk, err := framework.NewFramework()
	if err != nil {
		log.Fatalf("failed to create framework: %v", err)
	}
	if err = fwk.Start(context.Background()); err != nil {
		log.Fatalf("failed to start framework: %v", err)
	}
}
