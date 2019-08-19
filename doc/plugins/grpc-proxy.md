[中文](grpc-proxy-cn.md)
# grpc-proxy

HTTP(s) -> APISIX -> gRPC server

### Proto

#### Parameters
* `content`: `.proto` file's content.

#### Add a proto

Here's an example, adding a proto which `id` is `1`:

```shell
curl http://127.0.0.1:9080/apisix/admin/proto/1 -X PUT -d '
{
 "content" : "syntax = \"proto3\";
   package helloworld;
   service Greeter {
       rpc SayHello (HelloRequest) returns (HelloReply) {}
   }
   message HelloRequest {
       string name = 1;
   }
   message HelloReply {
       string message = 1;
      }"
}'
```

### Parameters

* `proto_id`: `.proto` content id.
* `service`:  the grpc service name.
* `method`:   the method name of grpc service.

### example

#### enable plugin

Here's an example, to enable the grpc-proxy plugin to specified route:

* attention: the route's option `service_protocal` must be `grpc`
* the grpc server example：[grpc_server_example](https://github.com/nic-chen/grpc_server_example)

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/111 -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/grpctest",
    "service_protocol": "grpc",
    "plugins": {
        "grpc-proxy": {
            "proto_id": "1",
            "service": "helloworld.Greeter",
            "method": "SayHello"
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:50051": 1
        }
    }
}'
```


#### test plugin

The above configuration proxy :
```shell
curl -i http://127.0.0.1:9080/grpctest
```

response:
```
HTTP/1.1 200 OK
Date: Fri, 16 Aug 2019 11:55:36 GMT
Content-Type: application/json
Transfer-Encoding: chunked
Connection: keep-alive
Server: APISIX web server
Proxy-Connection: keep-alive

{"message":"Hello world"}
```

This means that the proxying is working.

