---
title: batch-requests
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

## 目录

- [目录](#目录)
- [简介](#简介)
- [属性](#属性)
- [接口](#接口)
- [如何启用](#如何启用)
- [如何配置](#如何配置)
- [元数据](#元数据)
- [批量接口请求/响应](#批量接口请求响应)
  - [接口请求参数:](#接口请求参数)
    - [HttpRequest](#httprequest)
  - [接口响应参数：](#接口响应参数)
    - [HttpResponse](#httpresponse)
- [测试插件](#测试插件)
- [禁用插件](#禁用插件)

## 简介

`batch-requests` 插件可以一次接受多个请求并以 [http pipeline](https://en.wikipedia.org/wiki/HTTP_pipelining) 的方式在网关发起多个 http 请求，合并结果后再返回客户端，这在客户端需要访问多个接口时可以显著地提升请求性能。

> **提示**
>
> 外层的 Http 请求头会自动设置到每一个独立请求中，如果独立请求中出现相同键值的请求头，那么只有独立请求的请求头会生效。

## 属性

无

## 接口

插件会增加 `/apisix/batch-requests` 这个接口，你可能需要通过 [interceptors](../plugin-interceptors.md)
来保护它。

## 如何启用

本插件默认启用。

## 如何配置

默认本插件限制请求体的大小不能大于 1 MiB。这个限制可以通过 `apisix/admin/plugin_metadata/batch-requests` 来修改。

```shell
curl http://127.0.0.1:9080/apisix/admin/plugin_metadata/batch-requests -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "max_body_size": 4194304
}'
```

## 元数据

| 名称          | 类型    | 必选项 | 默认值  | 有效值 | 描述                           |
| ------------- | ------- | ------ | ------- | ------ | ------------------------------ |
| max_body_size | integer | 必选   | 1048576 | > 0    | 请求体的最大大小，单位为字节。 |

## 批量接口请求/响应

插件会为 `apisix` 创建一个 `/apisix/batch-requests` 的接口来处理你的批量请求。

### 接口请求参数:

| 参数名   | 类型                        | 可选项 | 默认值 | 有效值 | 描述                             |
| -------- | --------------------------- | ------ | ------ | ------ | -------------------------------- |
| query    | object                      | 可选   |        |        | 给所有请求都携带的 `QueryString` |
| headers  | object                      | 可选   |        |        | 给所有请求都携带的 `Header`      |
| timeout  | number                      | 可选   | 30000  |        | 聚合请求的超时时间，单位为 `ms`  |
| pipeline | [HttpRequest](#HttpRequest) | 必须   |        |        | Http 请求的详细信息              |

#### HttpRequest

| 参数名     | 类型    | 可选 | 默认值 | 有效值                                                                           | 描述                                                                      |
| ---------- | ------- | ---- | ------ | -------------------------------------------------------------------------------- | ------------------------------------------------------------------------- |
| version    | string  | 可选 | 1.1    | [1.0, 1.1]                                                                       | 请求用的 `http` 协议版本                                                  |
| method     | string  | 可选 | GET    | ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS", "CONNECT", "TRACE"] | 请求使用的 `http` 方法                                                    |
| query      | object  | 可选 |        |                                                                                  | 独立请求所携带的 `QueryString`, 如果 `Key` 和全局的有冲突，以此设置为主。 |
| headers    | object  | 可选 |        |                                                                                  | 独立请求所携带的 `Header`, 如果 `Key` 和全局的有冲突，以此设置为主。      |
| path       | string  | 必须 |        |                                                                                  | 请求路径                                                                  |
| body       | string  | 可选 |        |                                                                                  | 请求体                                                                    |
| ssl_verify | boolean | 可选 | false  |                                                                                  | 验证 SSL 证书与主机名是否匹配                                             |

### 接口响应参数：

返回值为一个 [HttpResponse](#HttpResponse) 的 `数组`。

#### HttpResponse

| 参数名  | 类型    | 描述                |
| ------- | ------- | ------------------- |
| status  | integer | Http 请求的状态码   |
| reason  | string  | Http 请求的返回信息 |
| body    | string  | Http 请求的响应体   |
| headers | object  | Http 请求的响应头   |

## 测试插件

你可以将要访问的请求信息传到网关的批量请求接口( `/apisix/batch-requests` )，网关会以 [http pipeline](https://en.wikipedia.org/wiki/HTTP_pipelining) 的方式自动帮你完成请求。

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

返回如下：

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

正常情况不需要禁用本插件，如有需要，在 `/conf/config.yaml` 中新建一个所需的 `plugins` 列表，以覆盖原列表。
