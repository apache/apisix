[English](grpc-proxy.md)
# grpc-proxy

通过APISIX代理gRPC连接，并使用APISIX的大部分特性管理你的grpc服务。 



### 参数

* `service_protocol`:  这个 route 的属性 `service_protocal` 必须设置为 `grpc`
* `uri`:   格式为 /service/method 如：/helloworld.Greeter/SayHello



### 示例

#### 创建代理grpc的route 

在指定 route 中，代理 gRPC 服务接口:

* 注意： 这个 route 的属性 `service_protocal` 必须设置为 `grpc`
* 注意： APISIX 使用 TLS 加密的 HTTP/2 暴露 gRPC 服务, 所以需要先[配置 SSL 证书](https://github.com/iresty/apisix/blob/master/doc/https-cn.md)
* 例子所代理的 gRPC 服务可参考：[grpc_server_example](https://github.com/nic-chen/grpc_server_example)

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


#### 测试

访问上面配置的 route：

```shell
$ grpcurl -insecure -import-path /pathtoprotos  -proto helloworld.proto  -d '{"name":"apisix"}' 127.0.0.1:9443 helloworld.Greeter.SayHello
{
  "message": "Hello apisix"
}
```

这表示已成功代理。

