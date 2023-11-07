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

//go:generate protoc --go_out=. --go_opt=paths=source_relative --go-grpc_out=. --go-grpc_opt=paths=source_relative proto/helloworld.proto
//go:generate protoc --go_out=. --go_opt=paths=source_relative --go-grpc_out=. --go-grpc_opt=paths=source_relative proto/import.proto
//go:generate protoc  --include_imports --descriptor_set_out=proto.pb --go_out=. --go_opt=paths=source_relative --go-grpc_out=. --go-grpc_opt=paths=source_relative proto/src.proto
//go:generate protoc --descriptor_set_out=echo.pb --include_imports --proto_path=$PWD/proto echo.proto
//go:generate protoc --go_out=. --go_opt=paths=source_relative --go-grpc_out=. --go-grpc_opt=paths=source_relative proto/echo.proto

// Package main implements a server for Greeter service.
package main

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"golang.org/x/net/http2"
	"golang.org/x/net/http2/h2c"

	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/credentials"
	"google.golang.org/grpc/reflection"
	"google.golang.org/grpc/status"

	pb "github.com/api7/grpc_server_example/proto"
)

var (
	grpcAddr      = ":10051"
	grpcsAddr     = ":10052"
	grpcsMtlsAddr string
	grpcHTTPAddr  string

	crtFilePath = "../t/cert/apisix.crt"
	keyFilePath = "../t/cert/apisix.key"
	caFilePath  string
)

func init() {
	flag.StringVar(&grpcAddr, "grpc-address", grpcAddr, "address for grpc")
	flag.StringVar(&grpcsAddr, "grpcs-address", grpcsAddr, "address for grpcs")
	flag.StringVar(&grpcsMtlsAddr, "grpcs-mtls-address", grpcsMtlsAddr, "address for grpcs in mTLS")
	flag.StringVar(&grpcHTTPAddr, "grpc-http-address", grpcHTTPAddr, "addresses for http and grpc services at the same time")
	flag.StringVar(&crtFilePath, "crt", crtFilePath, "path to certificate")
	flag.StringVar(&keyFilePath, "key", keyFilePath, "path to key")
	flag.StringVar(&caFilePath, "ca", caFilePath, "path to ca")
}

// server is used to implement helloworld.GreeterServer.
type server struct {
	// Embed the unimplemented server
	pb.UnimplementedGreeterServer
	pb.UnimplementedTestImportServer
	pb.UnimplementedEchoServer
}

// SayHello implements helloworld.GreeterServer
func (s *server) SayHello(ctx context.Context, in *pb.HelloRequest) (*pb.HelloReply, error) {
	log.Printf("Received: %v", in.Name)
	log.Printf("Enum Gender: %v", in.GetGender())
	msg := "Hello " + in.Name

	person := in.GetPerson()
	if person != nil {
		if person.GetName() != "" {
			msg += fmt.Sprintf(", name: %v", person.GetName())
		}
		if person.GetAge() != 0 {
			msg += fmt.Sprintf(", age: %v", person.GetAge())
		}
	}

	return &pb.HelloReply{
		Message: msg,
		Items:   in.GetItems(),
		Gender:  in.GetGender(),
	}, nil
}

// GetErrResp implements helloworld.GreeterServer
func (s *server) GetErrResp(ctx context.Context, in *pb.HelloRequest) (*pb.HelloReply, error) {
	st := status.New(codes.Unavailable, "Out of service")
	st, err := st.WithDetails(&pb.ErrorDetail{
		Code:    1,
		Message: "The server is out of service",
		Type:    "service",
	})
	if err != nil {
		panic(fmt.Sprintf("Unexpected error attaching metadata: %v", err))
	}

	return nil, st.Err()
}

func (s *server) SayHelloAfterDelay(ctx context.Context, in *pb.HelloRequest) (*pb.HelloReply, error) {
	select {
	case <-time.After(1 * time.Second):
		fmt.Println("overslept")
	case <-ctx.Done():
		errStr := ctx.Err().Error()
		if ctx.Err() == context.DeadlineExceeded {
			return nil, status.Error(codes.DeadlineExceeded, errStr)
		}
	}

	time.Sleep(1 * time.Second)

	log.Printf("Received: %v", in.Name)

	return &pb.HelloReply{Message: "Hello delay " + in.Name}, nil
}

func (s *server) Plus(ctx context.Context, in *pb.PlusRequest) (*pb.PlusReply, error) {
	log.Printf("Received: %v %v", in.A, in.B)
	return &pb.PlusReply{Result: in.A + in.B}, nil
}

func (s *server) EchoStruct(ctx context.Context, in *pb.StructRequest) (*pb.StructReply, error) {
	log.Printf("Received: %+v", in)

	return &pb.StructReply{
		Data: in.Data,
	}, nil
}

// SayHelloServerStream streams HelloReply back to the client.
func (s *server) SayHelloServerStream(req *pb.HelloRequest, stream pb.Greeter_SayHelloServerStreamServer) error {
	log.Printf("Received server side stream req: %v\n", req)

	// Say Hello 5 times.
	for i := 0; i < 5; i++ {
		if err := stream.Send(&pb.HelloReply{
			Message: fmt.Sprintf("Hello %s", req.Name),
		}); err != nil {
			return status.Errorf(codes.Unavailable, "Unable to stream request back to client: %v", err)
		}
	}
	return nil
}

// SayHelloClientStream receives a stream of HelloRequest from a client.
func (s *server) SayHelloClientStream(stream pb.Greeter_SayHelloClientStreamServer) error {
	log.Println("SayHello client side streaming has been initiated.")
	cache := ""
	for {
		req, err := stream.Recv()
		if err == io.EOF {
			return stream.SendAndClose(&pb.HelloReply{Message: cache})
		}
		if err != nil {
			return status.Errorf(codes.Unavailable, "Failed to read client stream: %v", err)
		}
		cache = fmt.Sprintf("%sHello %s!", cache, req.Name)
	}
}

// SayHelloBidirectionalStream establishes a bidirectional stream with the client.
func (s *server) SayHelloBidirectionalStream(stream pb.Greeter_SayHelloBidirectionalStreamServer) error {
	log.Println("SayHello bidirectional streaming has been initiated.")

	for {
		req, err := stream.Recv()
		if err == io.EOF {
			return stream.Send(&pb.HelloReply{Message: "stream ended"})
		}
		if err != nil {
			return status.Errorf(codes.Unavailable, "Failed to read client stream: %v", err)
		}

		// A small 0.5 sec sleep
		time.Sleep(500 * time.Millisecond)

		if err := stream.Send(&pb.HelloReply{Message: fmt.Sprintf("Hello %s", req.Name)}); err != nil {
			return status.Errorf(codes.Unknown, "Failed to stream response back to client: %v", err)
		}
	}
}

// SayMultipleHello implements helloworld.GreeterServer
func (s *server) SayMultipleHello(ctx context.Context, in *pb.MultipleHelloRequest) (*pb.MultipleHelloReply, error) {
	log.Printf("Received: %v", in.Name)
	log.Printf("Enum Gender: %v", in.GetGenders())
	msg := "Hello " + in.Name

	persons := in.GetPersons()
	if persons != nil {
		for _, person := range persons {
			if person.GetName() != "" {
				msg += fmt.Sprintf(", name: %v", person.GetName())
			}
			if person.GetAge() != 0 {
				msg += fmt.Sprintf(", age: %v", person.GetAge())
			}
		}
	}

	return &pb.MultipleHelloReply{
		Message: msg,
		Items:   in.GetItems(),
		Genders: in.GetGenders(),
	}, nil
}

func (s *server) Run(ctx context.Context, in *pb.Request) (*pb.Response, error) {
	return &pb.Response{Body: in.User.Name + " " + in.Body}, nil
}

func gRPCAndHTTPFunc(grpcServer *grpc.Server) http.Handler {
	return h2c.NewHandler(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		mux := http.NewServeMux()
		mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
			w.Write([]byte("hello http"))
		})

		if r.ProtoMajor == 2 && strings.Contains(r.Header.Get("Content-Type"), "application/grpc") {
			grpcServer.ServeHTTP(w, r)
		} else {
			mux.ServeHTTP(w, r)
		}
	}), &http2.Server{})
}

func main() {
	flag.Parse()

	go func() {
		lis, err := net.Listen("tcp", grpcAddr)
		if err != nil {
			log.Fatalf("failed to listen: %v", err)
		}
		s := grpc.NewServer()

		reflection.Register(s)
		pb.RegisterGreeterServer(s, &server{})
		pb.RegisterTestImportServer(s, &server{})
		pb.RegisterEchoServer(s, &server{})

		if err := s.Serve(lis); err != nil {
			log.Fatalf("failed to serve: %v", err)
		}
	}()

	go func() {
		lis, err := net.Listen("tcp", grpcsAddr)
		if err != nil {
			log.Fatalf("failed to listen: %v", err)
		}

		c, err := credentials.NewServerTLSFromFile(crtFilePath, keyFilePath)
		if err != nil {
			log.Fatalf("credentials.NewServerTLSFromFile err: %v", err)
		}
		s := grpc.NewServer(grpc.Creds(c))
		reflection.Register(s)
		pb.RegisterGreeterServer(s, &server{})
		if err := s.Serve(lis); err != nil {
			log.Fatalf("failed to serve: %v", err)
		}
	}()

	if grpcHTTPAddr != "" {
		go func() {
			lis, err := net.Listen("tcp", grpcHTTPAddr)
			if err != nil {
				log.Fatalf("failed to listen: %v", err)
			}
			s := grpc.NewServer()

			reflection.Register(s)
			pb.RegisterGreeterServer(s, &server{})
			pb.RegisterTestImportServer(s, &server{})

			if err := http.Serve(lis, gRPCAndHTTPFunc(s)); err != nil {
				log.Fatalf("failed to serve grpc: %v", err)
			}
		}()
	}

	if grpcsMtlsAddr != "" {
		go func() {
			lis, err := net.Listen("tcp", grpcsMtlsAddr)
			if err != nil {
				log.Fatalf("failed to listen: %v", err)
			}

			certificate, err := tls.LoadX509KeyPair(crtFilePath, keyFilePath)
			if err != nil {
				log.Fatalf("could not load server key pair: %s", err)
			}

			certPool := x509.NewCertPool()
			ca, err := os.ReadFile(caFilePath)
			if err != nil {
				log.Fatalf("could not read ca certificate: %s", err)
			}

			if ok := certPool.AppendCertsFromPEM(ca); !ok {
				log.Fatalf("failed to append client certs")
			}

			c := credentials.NewTLS(&tls.Config{
				ClientAuth:   tls.RequireAndVerifyClientCert,
				Certificates: []tls.Certificate{certificate},
				ClientCAs:    certPool,
			})
			s := grpc.NewServer(grpc.Creds(c))
			reflection.Register(s)
			pb.RegisterGreeterServer(s, &server{})
			if err := s.Serve(lis); err != nil {
				log.Fatalf("failed to serve: %v", err)
			}
		}()
	}

	signals := make(chan os.Signal)
	signal.Notify(signals, os.Interrupt, syscall.SIGTERM)
	sig := <-signals
	log.Printf("get signal %s, exit\n", sig.String())
}
