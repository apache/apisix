---
title: openwhisk
---

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

## Summary

- [**描述**](#描述)
- [**属性**](#属性)
- [**使用示例**](#使用示例)
- [**注意**](#注意)

## 描述

这个插件是用于支持集成 [Apache OpenWhisk](https://openwhisk.apache.org) 无服务器平台的插件，它可以被设置在路由上以替代 Upstream，其将接管请求并发送至 OpenWhisk 的 API 端点。

用户可以通过 APISIX 调用 OpenWhisk action，通过 JSON 传递请求参数并获取响应内容。

## 属性

| 名称 | 类型 | 必选项 | 默认值 | 有效值 | 描述 |
| -- | -- | -- | -- | -- | -- |
| api_host | string | 是 |   |   | OpenWhisk API 地址（例： https://localhost:3233） |
| ssl_verify | bool | 否 | true |   | 是否认证证书 |
| service_token | string | 是 |   |   | OpenWhisk 服务令牌 （格式为 `xxx:xxx`，调用 API 时通过 Basic Auth 传递） |
| namespace | string | 是 |   |   | OpenWhisk 命名空间 |
| action | string | 是 |   |   | OpenWhisk Action 名称（例：hello） |
| result | bool | 否 | true |   | 是否获取 Action 元数据（默认为执行函数并获取响应值；设置为 false 时，获取元数据，包含运行时、程序内容、限制等） |
| timeout | integer | 否 | 60000 |   | OpenWhisk Action 和 HTTP 的超时时间 (ms) |
| keepalive | bool | 否 | true |   | 是否启用 HTTP 长连接以避免过多的请求 |
| keepalive_timeout | integer | 否 | 60000 |   | HTTP 长连接超时时间 (ms) |
| keepalive_pool | integer | 否 | 5 |   | 连接池连接数限制 |

:::note
- `timeout` 属性同时控制 OpenWhisk Action 执行耗时和 APISIX 中 HTTP 客户端的超时时间。其中 OpenWhisk Action 调用时有可能会进行拉去运行时镜像和启动容器的工作，因此如果你设置的值过小，将可能导致大量请求失败。OpenWhisk 支持的超时时间范围为1ms至60000ms，建议至少设置为1000ms以上。
:::

## 使用示例

首先，你需要运行起 OpenWhisk 环境，以下是一个使用 OpenWhisk 独立模式的示例

```shell
docker run --rm -d \
  -h openwhisk --name openwhisk \
  -p 3233:3233 -p 3232:3232 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  openwhisk/standalone:nightly
docker exec openwhisk waitready
```

之后，你需要创建一个 Action 用于测试

```shell
wsk property set --apihost "http://localhost:3233" --auth "23bc46b1-71f6-4ed5-8c54-816aa4f8c502:123zO3xZCLrMN6v2BKK1dXYFpXlPkccOFqm12CdAsMgRU4VrNZ9lyGVCGuMDGIwP"
wsk action update test <(echo 'function main(){return {"ready":true}}') --kind nodejs:14
```

以下是一个示例，创建 Route 并启用此插件

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/hello",
    "plugins": {
        "openwhisk": {
            "api_host": "http://localhost:3233",
            "service_token": "23bc46b1-71f6-4ed5-8c54-816aa4f8c502:123zO3xZCLrMN6v2BKK1dXYFpXlPkccOFqm12CdAsMgRU4VrNZ9lyGVCGuMDGIwP",
            "namespace": "guest",
            "action": "test"
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {}
    }
}'
```

最后，你可以向这个路由发送请求，你将得到以下响应。同时，你可以通过移除路由中的 openwhsik 插件禁用它

```json
{"ready": true}
```

## 注意

当你需要提交数据时，你需要使用JSON格式的请求体。同时请注意请求体的大小，超过 `client_body_buffer_size` 设置的请求体将被完全丢弃，其值默认为 8KiB。
