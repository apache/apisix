#!/usr/bin/env bash

set -ex

# generate grpc object
protoc -I./a6 routes.proto --go_out=plugins=grpc:./a6
protoc -I=./a6 routes.proto --js_out=import_style=commonjs:./a6
protoc -I=./a6 routes.proto --grpc-web_out=import_style=commonjs,mode=grpcweb:./a6

# install client deps
npm install

# build server
CGO_ENABLED=0 go build -o grpc-web-server server.go && ./grpc-web-server -listen :19800 \
> grpc_web_server.log 2>&1 || (cat grpc_web_server.log && exit 1)&
