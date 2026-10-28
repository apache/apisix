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

注意：control API server 不应该被配置成监听公网地址。

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

只有启用了的插件才会被包含在返回结果中 `plugins` 部分。（返回结果中的）一些插件可能会缺失如 `consumer_schema` 或者 `type` 字段，这取决于插件的定义。

### GET /v1/healthcheck

引入自 2.3 版本

使用以下格式返回当前的 [health check](./tutorials/health-check.md) 状态

```json
[
  {
    "nodes": [
      {
        "ip": "52.86.68.46",
        "counter": {
          "http_failure": 0,
          "success": 0,
          "timeout_failure": 0,
          "tcp_failure": 0
        },
        "port": 80,
        "status": "healthy"
      },
      {
        "ip": "100.24.156.8",
        "counter": {
          "http_failure": 5,
          "success": 0,
          "timeout_failure": 0,
          "tcp_failure": 0
        },
        "port": 80,
        "status": "unhealthy"
      }
    ],
    "name": "/apisix/routes/1",
    "type": "http"
  }
]

```

每个 entry 包含以下字段：

* name: 资源 ID，健康检查的报告对象。
* type: 健康检查类型，取值为 `["http", "https", "tcp"]`。
* nodes: 检查节点列表。在健康检查器注册检查目标之前该字段为空数组（`[]`），健康检查器在上游第一次处理请求时才会创建。
* nodes[i].ip: IP 地址。
* nodes[i].port: 端口。
* nodes[i].status: 状态：`["healthy", "unhealthy", "mostly_healthy", "mostly_unhealthy"]`。
* nodes[i].counter.success: 成功计数器。
* nodes[i].counter.http_failure: HTTP 访问失败计数器。
* nodes[i].counter.tcp_failure: TCP 连接或读写的失败计数器。
* nodes[i].counter.timeout_failure: 超时计数器。

插件也可以对不属于任何上游的节点进行主动健康检查。[ai-proxy-multi](./plugins/ai-proxy-multi.md)
就是这样：它探测每个 LLM 实例，并在选择目标时跳过不健康的实例。这类检查器会额外带上两个字段：

```json
{
  "name": "/apisix/routes/1#plugins['ai-proxy-multi'].instances[0]",
  "plugin": "ai-proxy-multi",
  "meta": {
    "instance": "openai"
  },
  "type": "http",
  "nodes": [
    {
      "ip": "52.86.68.46",
      "port": 443,
      "status": "healthy",
      "counter": {
        "http_failure": 0,
        "success": 2,
        "timeout_failure": 0,
        "tcp_failure": 0
      }
    }
  ]
}
```

* plugin: 拥有该健康检查器的插件名。上游自身的健康检查器没有该字段。
* meta: 由插件填写，用于描述该检查器代表什么，内容由插件自行定义；`ai-proxy-multi` 在其中报告实例名。

用户也可以通过 `/v1/healthcheck/$src_type/$src_id` 来获取指定 health checker 的状态。

例如，`GET /v1/healthcheck/upstreams/1` 返回：

```json
{
  "nodes": [
    {
      "ip": "52.86.68.46",
      "counter": {
        "http_failure": 0,
        "success": 2,
        "timeout_failure": 0,
        "tcp_failure": 0
      },
      "port": 80,
      "status": "healthy"
    },
    {
      "ip": "100.24.156.8",
      "counter": {
        "http_failure": 5,
        "success": 0,
        "timeout_failure": 0,
        "tcp_failure": 0
      },
      "port": 80,
      "status": "unhealthy"
    }
  ],
  "type": "http"
  "name": "/apisix/routes/1"
}

```

:::note

上游只要配置了健康检查，就会出现在结果里面。在上游于任意一个 worker 进程处理过客户端请求之前，
健康检查器尚未创建，此时它的 `nodes` 为空数组。

:::

如果你使用浏览器访问该 API，你将得到一个网页：

![Health Check Status Page](https://raw.githubusercontent.com/apache/apisix/master/docs/assets/images/health_check_status_page.png)

### GET /v1/healthcheck/{src_type}/{src_id}/checkers

以数组形式返回某个资源拥有的全部健康检查器，数组元素与上文描述的 entry 结构一致。
一个资源可能拥有多个健康检查器——它自身的上游，加上每个插件实例各一个——而
`GET /v1/healthcheck/$src_type/$src_id` 返回的是单个对象，无法表达这种情况。

例如，`GET /v1/healthcheck/routes/1/checkers` 返回：

```json
[
  {
    "name": "/apisix/routes/1",
    "type": "http",
    "nodes": [...]
  },
  {
    "name": "/apisix/routes/1#plugins['ai-proxy-multi'].instances[0]",
    "plugin": "ai-proxy-multi",
    "meta": {
      "instance": "openai"
    },
    "type": "http",
    "nodes": [...]
  }
]
```

资源没有配置任何健康检查在这里不算错误：它拥有一个空的检查器集合，接口返回 `[]`。
只有资源本身不存在时才返回 `404`。

### POST /v1/gc

引入自 2.8 版本

在 http 子系统中触发一次全量 GC

注意，当你启用 stream proxy 时，APISIX 将为 stream 子系统运行另一个 Lua 虚拟机。它不会触发这个 Lua 虚拟机中的全量 GC。

### GET /v1/plugin_metadatas

引入自 3.0.0 版本

打印所有插件的元数据：

```json
[
    {
        "log_format": {
            "upstream_response_time": "$upstream_response_time"
        },
        "id": "file-logger"
    },
    {
        "ikey": 1,
        "skey": "val",
        "id": "example-plugin"
    }
]
```

### GET /v1/plugin_metadata/{plugin_name}

引入自 3.0.0 版本

打印指定插件的元数据：

```json
{
    "log_format": {
        "upstream_response_time": "$upstream_response_time"
    },
    "id": "file-logger"
}
```

这两个接口都会把 [ssl-session-ticket](./plugins/ssl-session-ticket.md) 元数据中的密钥替换为 `<redacted>`。

### GET /v1/tls_session_ticket

报告本节点业务 TLS 监听所用的 TLS session ticket 密钥，参见 [ssl-session-ticket](./plugins/ssl-session-ticket.md)。无论插件是否启用，该接口都存在。它只读取本节点的状态，不做任何修改，并且总是返回 `200`：请查看 `status` 与 `reason`。它从不返回密钥、密钥名或任何由密钥派生的内容。

```shell
curl http://127.0.0.1:9090/v1/tls_session_ticket
```

```json
{
    "status": "degraded",
    "reason": "module_not_active",
    "enabled": true,
    "key_count": 2,
    "effective_key_count": null,
    "fully_applied": false,
    "version": "b0181944:2",
    "source": "external",
    "source_version": "222",
    "updated_at": "2026-10-28T06:53:04Z",
    "updated_at_sec_ago": 1,
    "workers": {"total": 0, "applied": 0, "pending": 0, "failed": 0},
    "subsystems": {
        "http": {"applicable": false, "status": "degraded", "reason": "module_not_active",
                 "contexts": 0, "workers": {"total": 0, "applied": 0, "pending": 0, "failed": 0}},
        "stream": {"applicable": false, "status": "degraded", "reason": "module_not_active",
                   "contexts": 0, "workers": {"total": 0, "applied": 0, "pending": 0, "failed": 0}}
    },
    "generator": null,
    "warnings": ["default_keyring"],
    "last_apply_error": "the SSL layer does not consume the keys"
}
```

| 字段                | 描述 |
|---------------------|------|
| status、reason      | 本节点的结论，见下表。 |
| enabled             | 本节点是否允许业务 TLS 监听使用共享密钥（`apisix.ssl.ssl_session_tickets`），不表示实际已在使用。 |
| key_count           | 本节点应当使用的密钥数量：本地开关关闭、密钥停用、为空或不可用时为 0。 |
| effective_key_count | 本节点所有业务 TLS context 收敛后实际使用的密钥数量；未收敛时为 `null`。 |
| fully_applied       | 本节点所有业务 TLS context（包括仍在退出中的 worker 的 context）是否都已使用当前目标。 |
| version             | 本节点发布的目标的本地版本，不要跨节点比较。 |
| source、source_version | 密钥的来源及其元数据的 revision（etcd revision，standalone 模式下为配置版本），同一 etcd 集群内的节点可以据此比较。没有可读的密钥时为 `null`。 |
| updated_at、updated_at_sec_ago | 本节点发布该目标的时间（UTC）及距今的秒数，不作为健康指标。 |
| workers、subsystems | 各 worker 进程的进度，按子系统（`http`、`stream`）分项。 |
| generator           | 运行内置生成器的节点上为生成器的状态，其他节点为 `null`。 |
| warnings            | 不影响 status 的安全告警：`encryption_disabled` 或 `default_keyring`。 |
| last_apply_error    | 最近一次失败的原因，从不包含密钥。 |

| status / reason | 条件 |
|-----------------|------|
| `degraded` / `invalid_state`、`module_not_active` 或 `apply_failed` | 保存、加载或应用密钥失败，无论目标是什么。`module_not_active` 表示本节点没有任何模块把密钥应用到 TLS 监听。 |
| `degraded` / `worker_lag` | 有 worker 进程尚未应用当前目标。 |
| `off` / `local_switch_off`、`disabled_by_policy` 或 `empty_keys` | 所有 TLS 监听都已收敛为不使用共享密钥。 |
| `ok` / `null` | 所有 TLS 监听都在使用当前密钥。 |

没有 HTTP 子系统时（`proxy_mode: stream`），Control API 服务只提供这一个接口。
