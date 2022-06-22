---
title: request-id
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

`request-id` 插件通过 APISIX 为每一个请求代理添加唯一 ID（UUID），以用于追踪 API 请求。该插件在 `header_name` 已经在请求中存在时不会为请求添加新的 ID。

## 属性

| 名称                | 类型    | 必选项   | 默认值         | 有效值 | 描述                           |
| ------------------- | ------- | -------- | -------------- | ------ | ------------------------------ |
| header_name         | string  | 可选 | "X-Request-Id" |                       | Request ID header name         |
| include_in_response | boolean | 可选 | true          |                       | 是否需要在返回头中包含该唯一 ID |
| algorithm           | string  | 可选 | "uuid"         | ["uuid", "snowflake", "nanoid"] | ID 生成算法 |

:::warning

当使用 `snowflake` 算法时，请确保 APISIX 有权限写入 etcd。

:::

## 如何启用

创建一条路由并在该路由上启用 `request-id` 插件：

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/5 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

```shell
$ curl -i http://127.0.0.1:9080/hello
HTTP/1.1 200 OK
X-Request-Id: fe32076a-d0a5-49a6-a361-6c244c1df956
......
```

### 使用 snowflake 算法生成 ID

> 支持使用 snowflake 算法来生成 ID。
> 在决定使用 snowflake 时，请优先阅读一下文档。因为一旦启用配置信息则不可随意调整配置信息。否则可能会导致生成重复 ID。

snowflake 算法默认是不启用的，需要在 `conf/config.yaml` 中开启配置。

```yaml
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

#### 配置参数

| 名称                | 类型    | 必选项   | 默认值         | 有效值 | 描述                           |
| ------------------- | ------- | -------- | -------------- | ------ | ------------------------------ |
| enable                     | boolean  | 可选 | false          |  | 当设置为 true 时， 启用 snowflake 算法。      |
| snowflake_epoc             | integer  | 可选 | 1609459200000  |  | 起始时间戳（单位： 毫秒）|
| data_machine_bits          | integer  | 可选 | 12             |  | 最多支持机器（进程）数量 `1 << data_machine_bits` |
| sequence_bits              | integer  | 可选 | 10             |  | 每个节点每毫秒内最多产生 ID 数量 `1 << sequence_bits` |
| data_machine_ttl           | integer  | 可选 | 30             |  | `etcd` 中 `data_machine` 注册有效时间（单位： 秒）|
| data_machine_interval      | integer  | 可选 | 10             |  | `etcd` 中 `data_machine` 续约间隔时间（单位： 秒）|

- snowflake_epoc 默认起始时间为 `2021-01-01T00:00:00Z`, 按默认配置可以支持 `69 年` 大约可以使用到 `2090-09-07 15:47:35Z`
- data_machine_bits 对应的是 snowflake 定义中的 WorkerID 和 DatacenterID 的集合，插件会为每一个进程分配一个唯一 ID，最大支持进程数为 `pow(2, data_machine_bits)`。默认占 `12 bits` 最多支持 `4096` 个进程。
- sequence_bits 默认占 `10 bits`, 每个进程每毫秒最多生成 `1024` 个 ID

#### 配置示例

> snowflake 支持灵活配置来满足各式各样的需求

- snowflake 原版配置

> - 起始时间 2014-10-20T15:00:00.000Z， 精确到毫秒为单位。大约可以使用 `69 年`
> - 最多支持 `1024` 个进程
> - 每个进程每毫秒最多产生 `4096` 个 ID

```yaml
plugin_attr:
  request-id:
    snowflake:
      enable: true
      snowflake_epoc: 1413817200000
      data_machine_bits: 10
      sequence_bits: 12
```

## 禁用插件

在路由 `plugins` 配置块中删除 `request-id 配置，reload 即可禁用该插件，无需重启 APISIX。

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/5 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
