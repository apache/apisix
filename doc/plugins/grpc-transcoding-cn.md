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
* `option`:   proto 编码过程中的转换选项. [ "int64_as_string" / "enum_as_value" / "auto_default_values" / "enable_hooks" ]


### 示例

#### 使用 grpc-transcode 插件

在指定 route 中，代理 grpc 服务接口:

* 注意： 这个 route 的属性`service_protocol` 必须设置为 `grpc`
* 例子所代理的 grpc 服务可参考：[grpc_server_example](https://github.com/iresty/grpc_server_example)

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


#### 使用 grpc-transcode 插件的 pb_option 选项

在指定 route 中，代理 grpc 服务接口:

**选项清单**
 * 枚举类型
    > enum_as_name
    > enum_as_value

 * 64位整型
    > int64_as_number
    > int64_as_string
    > int64_as_hexstring

 * 使用默认值
    > auto_default_values
    > no_default_values
    > use_default_values
    > use_default_metatable

  * Hooks开关
    > enable_hooks
    > disable_hooks

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/23 -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/zeebe/WorkflowInstanceCreate",
    "service_protocol": "grpc",
    "plugins": {
        "grpc-transcode": {
         "proto_id": "1",
         "service": "gateway_protocol.Gateway",
         "method": "CreateWorkflowInstance",
         "pb_option":["int64_as_string"]
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:26500": 1
        }
    }
}'
```

#### 测试

访问上面配置的 route：

```
$ curl -i "http://127.0.0.1:9080/zeebe/WorkflowInstanceCreate?bpmnProcessId=order-process&version=1&variables=\{\"orderId\":\"7\",\"ordervalue\":99\}"
HTTP/1.1 200 OK
Date: Wed, 13 Nov 2019 03:38:27 GMT
Content-Type: application/json
Transfer-Encoding: chunked
Connection: keep-alive
grpc-encoding: identity
grpc-accept-encoding: gzip
Server: APISIX web server
Trailer: grpc-status
Trailer: grpc-message

{"workflowKey":"#2251799813685260","workflowInstanceKey":"#2251799813688013","bpmnProcessId":"order-process","version":1}
```

`"workflowKey":"#2251799813685260"` 这表示已成功。
