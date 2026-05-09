---
title: data-mask
keywords:
  - APISIX
  - API 网关
  - Plugin
  - data-mask
description: API 网关 Apache APISIX data-mask 插件可用于在请求数据写入访问日志或日志插件之前，对敏感字段进行掩码或脱敏处理。
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

`data-mask` 插件可在请求数据（查询参数、请求头、请求体）写入访问日志或日志插件（如 `file-logger`、`http-logger`）之前，对敏感字段进行掩码或脱敏处理。

该插件适用于防止凭证、令牌、支付卡号及其他敏感信息被写入日志的场景。

插件在 `log` 阶段运行，支持以下三种掩码动作：

- `remove`：从请求数据中完全删除该字段。
- `replace`：将字段值替换为固定字符串。
- `regex`：对字段值执行正则表达式替换。

## 属性

| 名称                | 类型    | 必选项 | 默认值    | 描述                                                                             |
|---------------------|---------|--------|-----------|----------------------------------------------------------------------------------|
| request             | array   | 否     |           | 需应用于请求数据的掩码规则列表。                                                  |
| max_body_size       | integer | 否     | 1048576   | 处理请求体时允许的最大字节数。超过此大小的请求体将跳过请求体掩码处理。            |
| max_req_post_args   | integer | 否     | 100       | 解析 `urlencoded` 请求体时允许的最大表单字段数量。                                |

`request` 数组中每个对象包含以下字段：

| 名称          | 类型   | 必选项                                    | 描述                                                                                                                         |
|---------------|--------|-------------------------------------------|------------------------------------------------------------------------------------------------------------------------------|
| type          | string | 是                                        | 要掩码的请求数据类型。可选值：`query`、`header`、`body`。                                                                   |
| name          | string | 是                                        | 要掩码的字段名称。对于 `query` 和 `header` 类型，填写参数名或请求头名；对于 `body` 类型且 `body_format` 为 `json` 时，填写 [JSONPath](https://goessner.net/articles/JsonPath/) 表达式。 |
| action        | string | 是                                        | 掩码动作。可选值：`remove`、`replace`、`regex`。                                                                            |
| body_format   | string | 当 `type` 为 `body` 时必填               | 请求体格式。可选值：`json`、`urlencoded`。                                                                                   |
| regex         | string | 当 `action` 为 `regex` 时必填            | 用于匹配字段值的正则表达式。可以在 `value` 中通过 `$1`、`$2` 等方式引用捕获组。                                             |
| value         | string | 当 `action` 为 `replace` 或 `regex` 时必填 | 替换值。当与 `action: regex` 配合使用时，可通过 `$1`、`$2` 等引用正则捕获组。                                               |

## 示例

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### 掩码查询参数

以下示例创建一条路由并配置 `data-mask` 插件对查询参数进行掩码处理：删除 `password` 参数，将 `token` 替换为固定字符串，并通过正则表达式对 `card` 号码进行部分掩码。

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
{
  "uri": "/anything",
  "plugins": {
    "data-mask": {
      "request": [
        {
          "type": "query",
          "name": "password",
          "action": "remove"
        },
        {
          "type": "query",
          "name": "token",
          "action": "replace",
          "value": "*****"
        },
        {
          "type": "query",
          "name": "card",
          "action": "regex",
          "regex": "(\\d+)\\-\\d+\\-\\d+\\-(\\d+)",
          "value": "$1-****-****-$2"
        }
      ]
    },
    "file-logger": {
      "path": "logs/access.log"
    }
  },
  "upstream": {
    "type": "roundrobin",
    "nodes": {
      "httpbin.org:80": 1
    }
  }
}'
```

发送一个包含敏感查询参数的请求：

```shell
curl "http://127.0.0.1:9080/anything?password=secret&token=mytoken&card=1234-5678-9012-3456"
```

在 `logs/access.log` 中，记录的请求 URI 将对敏感字段进行掩码处理：

```
/anything?token=*****&card=1234-****-****-3456
```

`password` 参数已被删除，`token` 被替换为 `*****`，卡号仅保留首尾各四位数字。

### 掩码请求头

以下示例对敏感请求头进行掩码处理：删除 `Authorization` 请求头，将 `X-API-Key` 替换为固定字符串，并通过正则表达式对自定义请求头 `X-Card-Number` 进行部分掩码。

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
{
  "uri": "/anything",
  "plugins": {
    "data-mask": {
      "request": [
        {
          "type": "header",
          "name": "Authorization",
          "action": "remove"
        },
        {
          "type": "header",
          "name": "X-API-Key",
          "action": "replace",
          "value": "[REDACTED]"
        },
        {
          "type": "header",
          "name": "X-Card-Number",
          "action": "regex",
          "regex": "(\\d+)\\-\\d+\\-\\d+\\-(\\d+)",
          "value": "$1-****-****-$2"
        }
      ]
    },
    "file-logger": {
      "path": "logs/access.log"
    }
  },
  "upstream": {
    "type": "roundrobin",
    "nodes": {
      "httpbin.org:80": 1
    }
  }
}'
```

发送一个包含敏感请求头的请求：

```shell
curl "http://127.0.0.1:9080/anything" \
  -H "Authorization: Bearer secret-token" \
  -H "X-API-Key: my-api-key" \
  -H "X-Card-Number: 1234-5678-9012-3456"
```

在 `logs/access.log` 中，记录的请求头将对敏感值进行掩码处理。

### 使用 JSONPath 掩码 JSON 请求体字段

以下示例对 JSON 请求体中的字段进行掩码处理：删除顶层的 `password` 字段，替换 `users` 数组中每个元素的 `token` 字段，并对每个用户的嵌套字段 `credit.card` 应用正则掩码。

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
{
  "uri": "/anything",
  "plugins": {
    "data-mask": {
      "request": [
        {
          "type": "body",
          "body_format": "json",
          "name": "$.password",
          "action": "remove"
        },
        {
          "type": "body",
          "body_format": "json",
          "name": "$.users[*].token",
          "action": "replace",
          "value": "*****"
        },
        {
          "type": "body",
          "body_format": "json",
          "name": "$.users[*].credit.card",
          "action": "regex",
          "regex": "(\\d+)\\-\\d+\\-\\d+\\-(\\d+)",
          "value": "$1-****-****-$2"
        }
      ]
    },
    "file-logger": {
      "include_req_body": true,
      "path": "logs/access.log"
    }
  },
  "upstream": {
    "type": "roundrobin",
    "nodes": {
      "httpbin.org:80": 1
    }
  }
}'
```

发送一个包含敏感字段的 JSON 请求体：

```shell
curl "http://127.0.0.1:9080/anything" \
  -H "Content-Type: application/json" \
  -d '{
    "password": "secret",
    "users": [
      {
        "name": "alice",
        "token": "tok_abc123",
        "credit": { "card": "1234-5678-9012-3456" }
      },
      {
        "name": "bob",
        "token": "tok_xyz789",
        "credit": { "card": "9876-5432-1098-7654" }
      }
    ]
  }'
```

在 `logs/access.log` 中，记录的请求体将对敏感字段进行掩码处理：

```json
{
  "users": [
    {
      "name": "alice",
      "token": "*****",
      "credit": { "card": "1234-****-****-3456" }
    },
    {
      "name": "bob",
      "token": "*****",
      "credit": { "card": "9876-****-****-7654" }
    }
  ]
}
```

`password` 字段已被删除，所有 `token` 字段被替换为 `*****`，卡号进行了部分掩码处理。

## 删除插件

当你需要删除该插件时，可以通过如下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
{
  "uri": "/anything",
  "plugins": {},
  "upstream": {
    "type": "roundrobin",
    "nodes": {
      "httpbin.org:80": 1
    }
  }
}'
```
