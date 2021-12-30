package main

import (
	"flag"
	"log"
	"net"

	"apisix.apache.org/plugin/grpc-web/a6"
	"google.golang.org/grpc"
	"google.golang.org/grpc/reflection"
)

var grpcListenAddress string

func init() {
	flag.StringVar(&grpcListenAddress, "listen", ":19800", "address for grpc")
}

func main() {
	flag.Parse()
	listen, err := net.Listen("tcp", grpcListenAddress)
	if err != nil {
		log.Fatalf("failed to listen gRPC-Web Test Server: %v", err)
	} else {
		log.Printf("successful to listen gRPC-Web Test Server, address %s", grpcListenAddress)
	}

	s := a6.RouteServer{}
	grpcServer := grpc.NewServer()
	reflection.Register(grpcServer)
	a6.RegisterRouteServiceServer(grpcServer, &s)

	if err = grpcServer.Serve(listen); err != nil {
		log.Fatalf("failed to serve: %v", err)
	}
}
