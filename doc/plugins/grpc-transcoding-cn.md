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

[English](grpc-transcoding.md)
# grpc-transcoding

HTTP(s) -> APISIX -> gRPC server

### Proto

#### 参数
* `content`: `.proto` 文件的内容

#### 添加proto

路径中最后的数字，会被用作 proto 的 id 做唯一标识，比如下面示例的 proto `id` 是 `1` ：

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

### 参数

* `proto_id`: `.proto`内容的id.
* `service`:  grpc服务名.
* `method`:   grpc服务中要调用的方法名.



### 示例

#### 使用 grpc-transcode 插件

在指定 route 中，代理 grpc 服务接口:

* 注意： 这个 route 的属性`service_protocal` 必须设置为 `grpc`
* 例子所代理的 grpc 服务可参考：[grpc_server_example](https://github.com/nic-chen/grpc_server_example)

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/111 -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/grpctest",
    "service_protocol": "grpc",
    "plugins": {
        "grpc-transcode": {
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


#### 测试

访问上面配置的 route：

```shell
$ curl -i http://127.0.0.1:9080/grpctest?name=world
HTTP/1.1 200 OK
Date: Fri, 16 Aug 2019 11:55:36 GMT
Content-Type: application/json
Transfer-Encoding: chunked
Connection: keep-alive
Server: APISIX web server
Proxy-Connection: keep-alive

{"message":"Hello world"}
```

这表示已成功代理。

