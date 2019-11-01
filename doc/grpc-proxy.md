[中文](grpc-proxy-cn.md)
# grpc-proxy

proxying gRPC traffic:
gRPC client -> APISIX -> gRPC server

### Parameters

* `service_protocol`:  the route's option `service_protocal` must be `grpc`
* `uri`:   format likes /service/method , Example：/helloworld.Greeter/SayHello



### Example

#### create proxying gRPC route 

Here's an example, to proxying gRPC service by specified route:

* attention: the route's option `service_protocal` must be `grpc`
* attention: APISIX use TLS‑encrypted HTTP/2 to expose gRPC service, so need to [config SSL certificate](https://github.com/iresty/apisix/blob/master/doc/https.md)
* the grpc server example：[grpc_server_example](https://github.com/nic-chen/grpc_server_example)

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -X PUT -d '
{
    "methods": ["POST", "GET"],
    "uri": "/helloworld.Greeter/SayHello",
    "service_protocol": "grpc",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:50051": 1
        }
    }
}'
```


#### testing

Invoking the route created before：

```shell
$ grpcurl -insecure -import-path /pathtoprotos  -proto helloworld.proto  -d '{"name":"apisix"}' 127.0.0.1:9443 helloworld.Greeter.SayHello
{
  "message": "Hello apisix"
}
```

This means that the proxying is working.

