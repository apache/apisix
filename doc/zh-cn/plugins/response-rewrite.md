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

- [English](../../plugins/response-rewrite.md)

# response-rewrite

该插件支持修改上游服务返回的 body 和 header 信息。

使用场景：
1、可以设置 `Access-Control-Allow-*` 等 header 信息，来实现 CORS (跨域资源共享)的功能。
2、另外也可以通过配置 status_code 和 header 里面的 Location 来实现重定向，当然如果只是需要重定向功能，最好使用 [redirect](redirect.md) 插件。

## 配置参数

| 名称        | 类型    | 必选项 | 默认值 | 有效值     | 描述                                                                                                                                   |
| ----------- | ------- | ------ | ------ | ---------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| status_code | integer | 可选   |        | [200, 598] | 修改上游返回状态码，默认保留原始响应代码。                                                                                             |
| body        | string  | 可选   |        |            | 修改上游返回的 `body` 内容，如果设置了新内容，header 里面的 content-length 字段也会被去掉                                              |
| body_base64 | boolean | 可选   | false  |            | 描述 `body` 字段是否需要 base64 解码之后再返回给客户端，用在某些图片和 Protobuffer 场景                                                |
| headers     | object  | 可选   |        |            | 返回给客户端的 `headers`，这里可以设置多个。头信息如果存在将重写，不存在则添加。想要删除某个 header 的话，把对应的值设置为空字符串即可 |

## 示例

### 开启插件

下面是一个示例，在指定的 route 上开启了 `response rewrite` 插件:

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/test/index.html",
    "plugins": {
        "response-rewrite": {
            "body": "{\"code\":\"ok\",\"message\":\"new json body\"}",
            "headers": {
                "X-Server-id": 3,
                "X-Server-status": "on"
            }
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:80": 1
        }
    }
}'
```

### 测试插件

基于上述配置进行测试：

```shell
curl -X GET -i  http://127.0.0.1:9080/test/index.html
```

如果看到返回的头部信息和内容都被修改了，即表示 `response rewrite` 插件生效了。

```shell
HTTP/1.1 200 OK
Date: Sat, 16 Nov 2019 09:15:12 GMT
Transfer-Encoding: chunked
Connection: keep-alive
X-Server-id: 3
X-Server-status: on

{"code":"ok","message":"new json body"}
```
