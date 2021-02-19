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

[English](../grpc-proxy.md)

# grpc-proxy

通过 APISIX 代理 gRPC 连接，并使用 APISIX 的大部分特性管理你的 gRPC 服务。

## 参数

* `scheme`: Route 对应的 Upstream 的 `scheme` 必须设置为 `grpc` 或者 `grpcs`
* `uri`: 格式为 /service/method 如：/helloworld.Greeter/SayHello

## 示例

### 创建代理 gRPC 的 Route

在指定 Route 中，代理 gRPC 服务接口:

* 注意：这个 Route 对应的 Upstream 的 `scheme` 必须设置为 `grpc` 或者 `grpcs`。
* 注意： APISIX 使用 TLS 加密的 HTTP/2 暴露 gRPC 服务, 所以需要先 [配置 SSL 证书](https.md)；
* 注意： APISIX 也支持通过纯文本的 HTTP/2 暴露 gRPC 服务，这不需要依赖 SSL，通常用于内网环境代理gRPC服务
* 下面例子所代理的 gRPC 服务可供参考：[grpc_server_example](https://github.com/api7/grpc_server_example)。

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["POST", "GET"],
    "uri": "/helloworld.Greeter/SayHello",
    "upstream": {
        "scheme": "grpc",
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:50051": 1
        }
    }
}'
```

### 测试 TLS 加密的 HTTP/2

访问上面配置的 Route：

```shell
grpcurl -insecure -import-path /pathtoprotos  -proto helloworld.proto  \
    -d '{"name":"apisix"}' 127.0.0.1:9443 helloworld.Greeter.SayHello
{
  "message": "Hello apisix"
}
```

这表示已成功代理。

### 测试纯文本的 HTTP/2

默认情况下，APISIX只在 `9443` 端口支持 TLS 加密的 HTTP/2。你也可以支持纯本文的 HTTP/2，只需要修改 `conf/config.yaml` 文件中的 `node_listen` 配置即可。

```yaml
apisix:
    node_listen:
        - port: 9080
          enable_http2: false
        - port: 9081
          enable_http2: true
```

访问上面配置的 Route：

```shell
grpcurl -plaintext -import-path /pathtoprotos  -proto helloworld.proto  \
    -d '{"name":"apisix"}' 127.0.0.1:9081 helloworld.Greeter.SayHello
{
  "message": "Hello apisix"
}
```

这表示已成功代理。

### gRPCS

如果你的 gRPC 服务使用了自己的 TLS 加密，即所谓的 `gPRCS` (gRPC + TLS)，那么需要修改 scheme 为 `grpcs`。继续上面的例子，50052 端口上跑的是 gPRCS 的服务，这时候应该这么配置：

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["POST", "GET"],
    "uri": "/helloworld.Greeter/SayHello",
    "upstream": {
        "scheme": "grpcs",
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:50052": 1
        }
    }
}'
```
