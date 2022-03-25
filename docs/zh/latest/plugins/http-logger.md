---
title: http-logger
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

`http-logger` 是一个插件，可将 Log 数据请求推送到 HTTP / HTTPS 服务器。

这将提供将 Log 数据请求作为 JSON 对象发送到监视工具和其他 HTTP 服务器的功能。

## 属性

| 名称             | 类型    | 必选项 | 默认值        | 有效值  | 描述                                             |
| ---------------- | ------- | ------ | ------------- | ------- | ------------------------------------------------ |
| uri              | string  | 必须   |               |         | `HTTP/HTTPS` 服务器的 URI。                   |
| auth_header      | string  | 可选   | ""            |         | 授权头部。                                    |
| timeout          | integer | 可选   | 3             | [1,...] | 发送请求后保持连接活动的时间。                   |
| name             | string  | 可选   | "http logger" |         | 标识 logger 的唯一标识符。                     |
| include_req_body | boolean | 可选   | false         | [false, true] | 是否包括请求 body。false： 表示不包含请求的 body ； true： 表示包含请求的 body 。 |
| include_resp_body| boolean | 可选   | false         | [false, true] | 是否包括响应体。包含响应体，当为`true`。 |
| include_resp_body_expr | array  | 可选    |           |         | 是否采集响体，基于 [lua-resty-expr](https://github.com/api7/lua-resty-expr)。 该选项需要开启 `include_resp_body`|
| concat_method    | string  | 可选   | "json"        | ["json", "new_line"] | 枚举类型： `json`、`new_line`。**json**: 对所有待发日志使用 `json.encode` 编码。**new_line**: 对每一条待发日志单独使用 `json.encode` 编码并使用 "\n" 连接起来。 |
| ssl_verify       | boolean | optional    | false          | [false, true] | 是否验证证书。 |

本插件支持使用批处理器来聚合并批量处理条目（日志/数据）。这样可以避免插件频繁地提交数据，默认设置情况下批处理器会每 `5` 秒钟或队列中的数据达到 `1000` 条时提交数据，如需了解或自定义批处理器相关参数设置，请参考 [Batch-Processor](../batch-processor.md#配置) 配置部分。

## 如何开启

这是有关如何为特定路由启用 `http-logger` 插件的示例。你可以在 [mockbin](http://mockbin.org/bin/create) 生成一个模拟 HTTP 服务器来浏览生成的日志

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
      "plugins": {
            "http-logger": {
                "uri": "http://mockbin.org/bin/:ID"
            }
       },
      "upstream": {
           "type": "roundrobin",
           "nodes": {
               "127.0.0.1:1980": 1
           }
      },
      "uri": "/hello"
}'
```

## 测试插件

> 成功：

```shell
$ curl -i http://127.0.0.1:9080/hello
HTTP/1.1 200 OK
...
hello, world
```

## 插件元数据设置

| 名称             | 类型    | 必选项 | 默认值        | 有效值  | 描述                                             |
| ---------------- | ------- | ------ | ------------- | ------- | ------------------------------------------------ |
| log_format       | object  | 可选   | {"host": "$host", "@timestamp": "$time_iso8601", "client_ip": "$remote_addr"} |         | 以 JSON 格式的键值对来声明日志格式。对于值部分，仅支持字符串。如果是以 `$` 开头，则表明是要获取 [APISIX 变量](../../../en/latest/apisix-variable.md) 或 [Nginx 内置变量](http://nginx.org/en/docs/varindex.html)。特别的，**该设置是全局生效的**，意味着指定 log_format 后，将对所有绑定 http-logger 的 Route 或 Service 生效。 |

### 设置日志格式示例

```shell
curl http://127.0.0.1:9080/apisix/admin/plugin_metadata/http-logger -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "log_format": {
        "host": "$host",
        "@timestamp": "$time_iso8601",
        "client_ip": "$remote_addr"
    }
}'
```

在日志收集处，将得到类似下面的日志：

```shell
{"host":"localhost","@timestamp":"2020-09-23T19:05:05-04:00","client_ip":"127.0.0.1","route_id":"1"}
{"host":"localhost","@timestamp":"2020-09-23T19:05:05-04:00","client_ip":"127.0.0.1","route_id":"1"}
```

## 禁用插件

在插件配置中删除相应的 json 配置以禁用 http-logger。APISIX 插件是热重载的，因此无需重新启动 APISIX：

```shell
$ curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/hello",
    "plugins": {},
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```
