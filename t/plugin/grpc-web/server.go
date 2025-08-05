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
	"context"
	"encoding/json"
	"flag"
	"log"
	"net"

	pb "apisix.apache.org/plugin/grpc-web/a6"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

type routeServiceServer struct {
	pb.UnimplementedRouteServiceServer
	savedRoutes []*pb.Route
}

func (rss *routeServiceServer) GetRoute(ctx context.Context, req *pb.Query) (*pb.Route, error) {
	var r *pb.Route
	if len(req.Name) <= 0 {
		return nil, status.Errorf(codes.InvalidArgument, "query params invalid")
	}

	for _, savedRoute := range rss.savedRoutes {
		if savedRoute.Name == req.Name {
			r = savedRoute
			break
		}
	}

	if r == nil {
		return nil, status.Errorf(codes.NotFound, "route not found")
	}

	return r, nil
}

func (rss *routeServiceServer) GetRoutes(req *pb.Query, srv pb.RouteService_GetRoutesServer) error {
	if len(rss.savedRoutes) <= 0 {
		return status.Errorf(codes.NotFound, "routes data is empty")
	}
	for _, savedRoute := range rss.savedRoutes {
		if err := srv.Send(savedRoute); err != nil {
			return err
		}
	}

	return nil
}

func (rss *routeServiceServer) GetError(ctx context.Context, req *pb.Query) (*pb.Route, error) {
	return nil, status.Errorf(codes.Internal, "execpted error")
}

func (rss *routeServiceServer) LoadRoutes() {
	if err := json.Unmarshal(exampleData, &rss.savedRoutes); err != nil {
		log.Fatalf("Failed to load default routes: %v", err)
	}
}

var exampleData = []byte(`[
{
	"name":"hello",
	"path":"/hello"
},
{
	"name":"world",
	"path":"/world"
}]`)

var ServerPort = ":50001"

func main() {
	flag.Parse()

	lis, err := net.Listen("tcp", ServerPort)
	if err != nil {
		log.Fatalf("failed to listen gRPC-Web Test Server: %v", err)
	} else {
		log.Printf("successful to listen gRPC-Web Test Server, address %s", ServerPort)
	}

	s := routeServiceServer{}
	s.LoadRoutes()
	var opts []grpc.ServerOption
	grpcServer := grpc.NewServer(opts...)
	pb.RegisterRouteServiceServer(grpcServer, &s)

	if err = grpcServer.Serve(lis); err != nil {
		log.Fatalf("failed to serve: %v", err)
	}
}
