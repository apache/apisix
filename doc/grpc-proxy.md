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

[中文](zh-cn/grpc-proxy.md)

# grpc-proxy

proxying gRPC traffic:
gRPC client -> APISIX -> gRPC server

## Parameters

* `service_protocol`:  the route's option `service_protocol` must be `grpc`
* `uri`:   format likes /service/method, Example：/helloworld.Greeter/SayHello

### Example

#### create proxying gRPC route

Here's an example, to proxying gRPC service by specified route:

* attention: the route's option `service_protocol` must be `grpc`
* attention: APISIX use TLS‑encrypted HTTP/2 to expose gRPC service, so need to [config SSL certificate](https.md)
* the grpc server example：[grpc_server_example](https://github.com/iresty/grpc_server_example)

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

#### testing

Invoking the route created before：

```shell
$ grpcurl -insecure -import-path /pathtoprotos  -proto helloworld.proto  -d '{"name":"apisix"}' 127.0.0.1:9443 helloworld.Greeter.SayHello
{
  "message": "Hello apisix"
}
```

This means that the proxying is working.
