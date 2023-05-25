---
title: batch-requests
keywords:
  - APISIX
  - Plugin
  - Batch Requests
description: 本文介绍了关于 Apache APISIX `batch-request` 插件的基本信息及使用方法。
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

## 描述

`batch-requests` 插件可以一次接受多个请求并以 [HTTP pipeline](https://en.wikipedia.org/wiki/HTTP_pipelining) 的方式在网关发起多个 HTTP 请求，合并结果后再返回客户端。

在客户端需要访问多个 API 的情况下，这将显著提高性能。

:::note

外部批处理请求的 HTTP 请求头（除了以 `Content-` 开始的请求头，例如：`Content-Type`）适用于**批处理**中的每个请求。

如果在外部请求和单个调用中都指定了相同的 HTTP 请求头，则单个调用的请求头优先。

:::

## 属性

无。

## 接口

该插件会增加 `/apisix/batch-requests` 接口。

:::note

你需要通过 [public-api](../../../zh/latest/plugins/public-api.md) 插件来暴露它。

:::

## 启用插件

该插件默认是禁用状态，你可以在配置文件（`./conf/config.yaml`）添加如下配置启用 `batch-requests` 插件：

```yaml title="conf/config.yaml"
plugins:
  - ...
  - batch-requests
```

## 配置插件

默认情况下，可以发送到 `/apisix/batch-requests` 的最大请求体不能大于 1 MiB。你可以通过 `apisix/admin/plugin_metadata/batch-requests` 更改插件的此配置：

```shell
curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/batch-requests \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "max_body_size": 4194304
}'
```

## 元数据

| 名称          | 类型     | 必选项 | 默认值   | 有效值 | 描述                          |
| ------------- | ------- | -------| ------- | ------ | ---------------------------- |
| max_body_size | integer | 是     | 1048576 |[1, ...]| 请求体的最大大小，单位：bytes。 |

## 请求和响应格式

该插件会为 `apisix` 创建一个 `/apisix/batch-requests` 的接口，用来处理批量请求。

### 请求参数

| 参数名   | 类型                                 | 必选项 | 默认值 |  描述                             |
| -------- |------------------------------------| ------ | ------ |  -------------------------------- |
| query    | object                             | 否     |        | 给所有请求都携带的 `query string`。 |
| headers  | object                             | 否     |        | 给所有请求都携带的 `header`。       |
| timeout  | number                             | 否     | 30000  | 聚合请求的超时时间，单位为 `ms`。    |
| pipeline | array[[HttpRequest](#httprequest)] | 是     |        | HTTP 请求的详细信息。               |

#### HttpRequest

| 参数名      | 类型    | 必选项    | 默认值  | 有效值                                                                            | 描述                                                                  |
| ---------- | ------- | -------- | ------- | -------------------------------------------------------------------------------- | --------------------------------------------------------------------- |
| version    | string  | 否       | 1.1     | [1.0, 1.1]                                                                       | 请求所使用的 HTTP 协议版本。                                              |
| method     | string  | 否       | GET     | ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS", "CONNECT", "TRACE"] | 请求使用的 HTTP 方法。                                                   |
| query      | object  | 否       |         |                                                                                  | 独立请求所携带的 `query string`, 如果 `Key` 和全局的有冲突，以此设置为主。 |
| headers    | object  | 否       |         |                                                                                  | 独立请求所携带的 `header`, 如果 `Key` 和全局的有冲突，以此设置为主。       |
| path       | string  | 是       |         |                                                                                  | HTTP 请求路径。                                                        |
| body       | string  | 否       |         |                                                                                  | HTTP 请求体。                                                          |
| ssl_verify | boolean | 否       | false   |                                                                                  | 验证 SSL 证书与主机名是否匹配。                                          |

### 响应参数

返回值是一个 [HttpResponse](#httpresponse) 的`数组`。

#### HttpResponse

| 参数名   | 类型    | 描述                 |
| ------- | ------- | ------------------- |
| status  | integer | HTTP 请求的状态码。   |
| reason  | string  | HTTP 请求的返回信息。 |
| body    | string  | HTTP 请求的响应体。   |
| headers | object  | HTTP 请求的响应头。   |

## 修改自定义 URI

你可以通过 [public-api](../../../en/latest/plugins/public-api.md) 插件设置自定义 URI。

只需要在创建路由时设置所需的 URI 并更改 `public-api` 插件的配置：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/br \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/batch-requests",
    "plugins": {
        "public-api": {
            "uri": "/apisix/batch-requests"
        }
    }
}'
```

## 测试插件

首先，你需要为 `batch-requests` 插件的 API 创建一个路由，它将使用 [public-api](../../../en/latest/plugins/public-api.md) 插件。

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/apisix/batch-requests",
    "plugins": {
        "public-api": {}
    }
}'
```

之后，你就可以将要访问的请求信息传到网关的批量请求接口（`/apisix/batch-requests`）了，网关会以 [http pipeline](https://en.wikipedia.org/wiki/HTTP_pipelining) 的方式自动帮你完成请求。

```shell
curl --location --request POST 'http://127.0.0.1:9080/apisix/batch-requests' \
--header 'Content-Type: application/json' \
--data '{
    "headers": {
        "Content-Type": "application/json",
        "admin-jwt":"xxxx"
    },
    "timeout": 500,
    "pipeline": [
        {
            "method": "POST",
            "path": "/community.GiftSrv/GetGifts",
            "body": "test"
        },
        {
            "method": "POST",
            "path": "/community.GiftSrv/GetGifts",
            "body": "test2"
        }
    ]
}'
```

正常返回结果如下：

```json
[
  {
    "status": 200,
    "reason": "OK",
    "body": "{\"ret\":500,\"msg\":\"error\",\"game_info\":null,\"gift\":[],\"to_gets\":0,\"get_all_msg\":\"\"}",
    "headers": {
      "Connection": "keep-alive",
      "Date": "Sat, 11 Apr 2020 17:53:20 GMT",
      "Content-Type": "application/json",
      "Content-Length": "81",
      "Server": "APISIX web server"
    }
  },
  {
    "status": 200,
    "reason": "OK",
    "body": "{\"ret\":500,\"msg\":\"error\",\"game_info\":null,\"gift\":[],\"to_gets\":0,\"get_all_msg\":\"\"}",
    "headers": {
      "Connection": "keep-alive",
      "Date": "Sat, 11 Apr 2020 17:53:20 GMT",
      "Content-Type": "application/json",
      "Content-Length": "81",
      "Server": "APISIX web server"
    }
  }
]
```

## 禁用插件

如果你想禁用插件，可以将 `batch-requests` 从配置文件中的插件列表删除，重新加载 APISIX 后即可生效。

```yaml title="conf/config.yaml"
plugins:    # plugin list
  - ...
```
