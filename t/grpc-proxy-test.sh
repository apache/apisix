#!/usr/bin/env bash

#test grpc proxy
curl http://127.0.0.1:9080/apisix/admin/routes/1 -X PUT -d '
{
    "methods": ["POST"],        
    "uri": "/helloworld.Greeter/SayHello",
    "service_protocol": "grpc",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:50051": 1
        }
    }
}'

./build-cache/grpcurl -insecure -import-path ./build-cache/proto -proto helloworld.proto -d '{"name":"apisix"}' 127.0.0.1:9443 helloworld.Greeter.SayHello
