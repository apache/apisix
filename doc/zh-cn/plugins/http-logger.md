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

- [English](../../plugins/http-logger.md)

# 目录

- [**定义**](#name)
- [**属性列表**](#attributes)
- [**如何开启**](#how-to-enable)
- [**测试插件**](#test-plugin)
- [**禁用插件**](#disable-plugin)

## 定义

`http-logger` 是一个插件，可将Log数据请求推送到 HTTP / HTTPS 服务器。

这将提供将 Log 数据请求作为JSON对象发送到监视工具和其他 HTTP 服务器的功能。

## 属性列表

| 名称             | 类型    | 必选项 | 默认值        | 有效值  | 描述                                             |
| ---------------- | ------- | ------ | ------------- | ------- | ------------------------------------------------ |
| uri              | string  | 必须   |               |         | 服务器的 URI                                     |
| auth_header      | string  | 可选   | ""            |         | 授权头部                                         |
| timeout          | integer | 可选   | 3             | [1,...] | 发送请求后保持连接活动的时间                     |
| name             | string  | 可选   | "http logger" |         | 标识 logger 的唯一标识符                         |
| batch_max_size   | integer | 可选   | 1000          | [1,...] | 每批的最大大小                                   |
| inactive_timeout | integer | 可选   | 5             | [1,...] | 刷新缓冲区的最大时间（以秒为单位）               |
| buffer_duration  | integer | 可选   | 60            | [1,...] | 必须先处理批次中最旧条目的最长期限（以秒为单位） |
| max_retry_count  | integer | 可选   | 0             | [0,...] | 从处理管道中移除之前的最大重试次数               |
| retry_delay      | integer | 可选   | 1             | [0,...] | 如果执行失败，则应延迟执行流程的秒数             |
| include_req_body | boolean | 可选   |               |         | 是否包括请求 body                                |

## 如何开启

1. 这是有关如何为特定路由启用 http-logger 插件的示例。

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
      "plugins": {
            "http-logger": {
                 "uri": "127.0.0.1:80/postendpoint?param=1"
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

> 成功:

```shell
$ curl -i http://127.0.0.1:9080/hello
HTTP/1.1 200 OK
...
hello, world
```

## 禁用插件

在插件配置中删除相应的 json 配置以禁用 http-logger。APISIX 插件是热重载的，因此无需重新启动 APISIX：

```shell
$ curl http://127.0.0.1:2379/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d value='
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
