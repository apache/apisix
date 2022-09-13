---
title: request-id
keywords:
  - APISIX
  - API 网关
  - Request ID
description: 本文介绍了 Apache APISIX request-id 插件的相关操作，你可以使用此插件为每个请求代理添加 unique ID 来追踪 API 请求。
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

`request-id` 插件通过 APISIX 为每一个请求代理添加 unique ID 用于追踪 API 请求。

:::note 注意

如果请求已经配置了 `header_name` 属性的请求头，该插件将不会为请求添加 unique ID。

:::

## 属性

| 名称                | 类型    | 必选项   | 默认值         | 有效值 | 描述                           |
| ------------------- | ------- | -------- | -------------- | ------ | ------------------------------ |
| header_name         | string  | 否 | "X-Request-Id" |                       | unique ID 的请求头的名称。         |
| include_in_response | boolean | 否 | true          |                       | 当设置为 `true` 时，将 unique ID 加入返回头。 |
| algorithm           | string  | 否 | "uuid"         | ["uuid", "snowflake", "nanoid"] | 指定的 unique ID 生成算法。 |

### 使用 snowflake 算法生成 unique ID

:::caution 警告

- 当使用 `snowflake` 算法时，请确保 APISIX 有权限写入 etcd。
- 在决定使用 `snowflake` 算法时，请仔细阅读本文档了解配置细节。因为一旦启用相关配置信息后，就不能随意调整，否则可能会导致生成重复的 ID。

:::

`snowflake` 算法支持灵活配置来满足各种需求，可配置的参数如下：

| 名称                | 类型    | 必选项   | 默认值         | 描述                           |
| ------------------- | ------- | -------- | -------------- | ------------------------------ |
| enable                     | boolean  | 否 | false          | 当设置为 `true` 时， 启用 `snowflake` 算法。      |
| snowflake_epoc             | integer  | 否 | 1609459200000  | 起始时间戳，以毫秒为单位。默认为 `2021-01-01T00:00:00Z`, 可以支持 `69 年`到 `2090-09-07 15:47:35Z`。 |
| data_machine_bits          | integer  | 否 | 12             | 最多支持的机器（进程）数量。 与 `snowflake` 定义中 `workerIDs` 和 `datacenterIDs` 的集合对应，插件会为每一个进程分配一个 unique ID。最大支持进程数为 `pow(2, data_machine_bits)`。即对于默认值 `12 bits`，最多支持的进程数为 `4096`。|
| sequence_bits              | integer  | 否 | 10             | 每个节点每毫秒内最多产生的 ID 数量。 每个进程每毫秒最多产生 `1024` 个 ID。 |
| data_machine_ttl           | integer  | 否 | 30             | etcd 中 `data_machine` 注册有效时间，以秒为单位。 |
| data_machine_interval      | integer  | 否 | 10             | etcd 中 `data_machine` 续约间隔时间，以秒为单位。 |

如果你需要使用 `snowflake` 算法，请务必在配置文件 `./conf/config.yaml` 中添加以下参数：

```yaml title="conf/config.yaml"
plugin_attr:
  request-id:
    snowflake:
      enable: true
      snowflake_epoc: 1609459200000
      data_machine_bits: 12
      sequence_bits: 10
      data_machine_ttl: 30
      data_machine_interval: 10
```

## 启用插件

以下示例展示了如何在指定路由上启用 `request-id` 插件：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/5 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/hello",
    "plugins": {
        "request-id": {
            "include_in_response": true
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:8080": 1
        }
    }
}'
```

## 测试插件

按上述配置启用插件后，APISIX 将为你的每个请求创建一个 unique ID。

使用 `curl` 命令请求该路由：

```shell
curl -i http://127.0.0.1:9080/hello
```

返回的 HTTP 响应头中如果带有 `200` 状态码，且每次返回不同的 `X-Request-Id`，则表示插件生效：

```shell
HTTP/1.1 200 OK
X-Request-Id: fe32076a-d0a5-49a6-a361-6c244c1df956
```

## 禁用插件

当你需要禁用该插件时，可以通过以下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/5 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/get",
    "plugins": {
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:8080": 1
        }
    }
}'
```
