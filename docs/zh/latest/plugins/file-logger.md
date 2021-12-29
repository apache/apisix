---
title: file-logger
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

- [**定义**](#定义)
- [**属性列表**](#属性)
- [**如何开启**](#如何启用)
- [**测试插件**](#测试插件)
- [**插件元数据设置**](#插件元数据设置)
- [**禁用插件**](#禁用插件)

## 定义

`file-logger` 是一个插件，可将 Log 数据流推送到指定位置，例如，可以自定义输入路径：`logs/file.log`。

## 属性列表

| 名称             | 类型    | 必选项 | 默认值        | 有效值  | 描述                                             |
| ---------------- | ------- | ------ | ------------- | ------- | ------------------------------------------------ |
| path              | string  | 必须   |               |         | 自定义输入文件路径                   |
| custom_fields_by_lua      | object  | 可选   |             |         | 键值对列表，其中键是日志字段的名称，值为一段 `lua` 代码，其返回值设置或者替换日志字段值                                    |

## 如何开启

这是有关如何为特定路由启用 `file-logger` 插件的示例。

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
      "plugins": {
            "file-logger": {
                "path": "logs/file.log",
                "custom_fields_by_lua": {"route_id": "return nil"}
            }
       },
      "upstream": {
           "type": "roundrobin",
           "nodes": {
               "127.0.0.1:3030": 1
           }
      },
      "uri": "/api/hello"
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

然后你可以在对应的 `logs` 目录下找到 `file.log` 文件，且该日志中现有字段的 `route_id` 被删除。初次打开该文件时会额外生成一个 `file_pointer` 文件，它用来储存打开目标输入文件的指针。

> 通过 control API 重新打开该日志文件

```shell
$ curl -i http://localhost:9090/plugin/file-logger/reopen?reopen
```

然后下次请求时，会将之前所有缓冲区的日志数据刷新到日志文件中。

## 插件元数据设置

| 名称             | 类型    | 必选项 | 默认值        | 有效值  | 描述                                             |
| ---------------- | ------- | ------ | ------------- | ------- | ------------------------------------------------ |
| log_format       | object  | 可选   | {"host": "$host", "@timestamp": "$time_iso8601", "client_ip": "$remote_addr"} |         | 以 JSON 格式的键值对来声明日志格式。对于值部分，仅支持字符串。如果是以 `$` 开头，则表明是要获取 __APISIX__ 变量或 [Nginx 内置变量](http://nginx.org/en/docs/varindex.html)。特别的，**该设置是全局生效的**，意味着指定 log_format 后，将对所有绑定 http-logger 的 Route 或 Service 生效。 |

**APISIX 变量**

|       变量名      |           描述          |      使用示例    |
|------------------|-------------------------|----------------|
| route_id         | `route` 的 id           | $route_id      |
| route_name       | `route` 的 name         | $route_name    |
| service_id       | `service` 的 id         | $service_id    |
| service_name     | `service` 的 name       | $service_name  |
| consumer_name    | `consumer` 的 username  | $consumer_name |

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
