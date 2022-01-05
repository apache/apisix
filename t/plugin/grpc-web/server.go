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
	"flag"
	"log"
	"net"

	"apisix.apache.org/plugin/grpc-web/a6"
	"google.golang.org/grpc"
	"google.golang.org/grpc/reflection"
)

var grpcListenAddress string

func init() {
	flag.StringVar(&grpcListenAddress, "listen", ":50001", "address for grpc")
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
