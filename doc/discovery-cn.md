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

# 集成服务发现注册中心

## 开启服务发现

首先要在 `conf/config.yaml` 文件中增加如下配置，以选择注册中心的类型：

```yaml
apisix:
  discovery: eureka
```

## Eureka 的配置

在 `conf/config.yaml` 增加如下配置：

```yaml
eureka:
  urls: http://${usename}:${passowrd}@${eureka_host1}:${eureka_port1}/eureka/,http://${usename}:${passowrd}@${eureka_host2}:${eureka_port2}/eureka/
```

`eureka.urls` 是 eureka 的服务器地址，如果是多个服务器的话，使用逗号隔开。

如果 eureka 的地址是 `http://127.0.0.1:8761/` ，并且不需要用户名和密码验证的话，配置如下：

```yaml
eureka:
  urls: http://127.0.0.1:8761/eureka/
```

## 路由配置

如果希望 uri 为 "/a/*" 的请求路由到注册中心名为 "a_service" 的服务上时：

```shell
$ curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -i -d '
{
    "uri": "/a/*",
    "upstream_id": "a_service"
}'

HTTP/1.1 201 Created
Date: Sat, 31 Aug 2019 01:17:15 GMT
Content-Type: text/plain
Transfer-Encoding: chunked
Connection: keep-alive
Server: APISIX web server

{"node":{"value":{"uri":"\/a\/*","upstream_id": "a_service"},"createdIndex":61925,"key":"\/apisix\/routes\/1","modifiedIndex":61925},"action":"create"}
```

同理，将 Service 中的 `upstream_id` 指向服务名，也是可以达到相同的效果。
