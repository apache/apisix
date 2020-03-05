<!--
#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
-->

[English](grpc-proxy.md)
# grpc-proxy

通过 APISIX 代理 gRPC 连接，并使用 APISIX 的大部分特性管理你的 gRPC 服务。


### 参数

* `service_protocol`:  这个 Route 的属性 `service_protocol` 必须设置为 `grpc`
* `uri`:   格式为 /service/method 如：/helloworld.Greeter/SayHello


### 示例

#### 创建代理 gRPC 的 Route

在指定 Route 中，代理 gRPC 服务接口:

* 注意： 这个 Route 的属性 `service_protocol` 必须设置为 `grpc`；
* 注意： APISIX 使用 TLS 加密的 HTTP/2 暴露 gRPC 服务, 所以需要先 [配置 SSL 证书](https-cn.md)；
* 下面例子所代理的 gRPC 服务可供参考：[grpc_server_example](https://github.com/iresty/grpc_server_example)。

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

访问上面配置的 Route：

```shell
grpcurl -insecure -import-path /pathtoprotos  -proto helloworld.proto  \
    -d '{"name":"apisix"}' 127.0.0.1:9443 helloworld.Greeter.SayHello
{
  "message": "Hello apisix"
}
```

这表示已成功代理。
