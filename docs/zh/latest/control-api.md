---
title: Control API
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

control API 可以被用来：

* 暴露 APISIX 内部状态信息
* 控制单个 APISIX 的数据平面的行为

默认情况下，control API 是启用的，监听 `127.0.0.1:9090`。你可以通过修改 `apisix/conf/config.yaml` 中的 control 部分来更改设置，如下：

```yaml
apisix:
  ...
  enable_control: true
  control:
    ip: "127.0.0.1"
    port: 9090
```

插件的 control API 在默认情况下不支持参数匹配，如果想启用参数匹配功能可以在 control 部分添加 `router: 'radixtree_uri_with_parameter'`

注意: control API server 不应该被配置成监听公网地址。

## 通过插件添加的 control API

APISIX 中一些插件添加了自己的 control API。如果你对他们感兴趣，请参阅对应插件的文档。

## 独立于插件的 control API

以下是支持的 API:

### GET /v1/schema

引入自 2.2 版本

使用以下格式返回被该 APISIX 实例使用的 json schema：

```json
{
    "main": {
        "route": {
            "properties": {...}
        },
        "upstream": {
            "properties": {...}
        },
        ...
    },
    "plugins": {
        "example-plugin": {
            "consumer_schema": {...},
            "metadata_schema": {...},
            "schema": {...},
            "type": ...,
            "priority": 0,
            "version": 0.1
        },
        ...
    },
    "stream-plugins": {
        "mqtt-proxy": {
            ...
        },
        ...
    }
}
```

只有启用了的插件才会被包含在返回结果中 `plugins` 部分。(返回结果中的)一些插件可能会缺失如 `consumer_schema` 或者 `type` 字段，这取决于插件的定义。

### GET /v1/healthcheck

引入自 2.3 版本

使用以下格式返回当前的 [health check](health-check.md) 状态

```json
[
    {
        "healthy_nodes": [
            {
                "host": "127.0.0.1",
                "port": 1980,
                "priority": 0,
                "weight": 1
            }
        ],
        "name": "upstream#/upstreams/1",
        "nodes": [
            {
                "host": "127.0.0.1",
                "port": 1980,
                "priority": 0,
                "weight": 1
            },
            {
                "host": "127.0.0.2",
                "port": 1988,
                "priority": 0,
                "weight": 1
            }
        ],
        "src_id": "1",
        "src_type": "upstreams"
    },
    {
        "healthy_nodes": [
            {
                "host": "127.0.0.1",
                "port": 1980,
                "priority": 0,
                "weight": 1
            }
        ],
        "name": "upstream#/routes/1",
        "nodes": [
            {
                "host": "127.0.0.1",
                "port": 1980,
                "priority": 0,
                "weight": 1
            },
            {
                "host": "127.0.0.1",
                "port": 1988,
                "priority": 0,
                "weight": 1
            }
        ],
        "src_id": "1",
        "src_type": "routes"
    }
]
```

每个 entry 包含以下字段：

* src_type：表示 health checker 的来源。值是 `[routes,services,upstreams]` 其中之一
* src_id：表示创建 health checker 的对象的 id。例如，假设 id 为 1 的 Upstream 对象创建了一个 health checker，那么 `src_type` 就是 `upstreams`，`src_id` 就是 1
* name： 表示 health checker 的名称
* nodes： health checker 的目标节点
* healthy_nodes： 表示 health checker 检测到的健康节点

用户也可以通过 `/v1/healthcheck/$src_type/$src_id` 来获取指定 health checker 的状态。

例如，`GET /v1/healthcheck/upstreams/1` 返回：

```json
{
    "healthy_nodes": [
        {
            "host": "127.0.0.1",
            "port": 1980,
            "priority": 0,
            "weight": 1
        }
    ],
    "name": "upstream#/upstreams/1",
    "nodes": [
        {
            "host": "127.0.0.1",
            "port": 1980,
            "priority": 0,
            "weight": 1
        },
        {
            "host": "127.0.0.2",
            "port": 1988,
            "priority": 0,
            "weight": 1
        }
    ],
    "src_id": "1",
    "src_type": "upstreams"
}
```

### POST /v1/gc

引入自 2.8 版本

在 http 子系统中触发一次全量 GC

注意，当你启用 stream proxy 时，APISIX 将为 stream 子系统运行另一个 Lua 虚拟机。它不会触发这个 Lua 虚拟机中的全量 GC。
