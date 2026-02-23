---
title: ua-restriction
keywords:
  - Apache APISIX
  - API 网关
  - UA restriction
description: ua-restriction 插件使用用户代理的允许列表或拒绝列表来限制对上游资源的访问，防止网络爬虫过载并增强 API 安全性。
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

<head>
  <link rel="canonical" href="https://docs.api7.ai/hub/ua-restriction" />
</head>

## 描述

`ua-restriction` 插件支持通过配置用户代理的允许列表或拒绝列表来限制对上游资源的访问。一个常见的用例是防止网络爬虫使上游资源过载并导致服务降级。

## 属性

| 名称    | 类型          | 必选项 | 默认值 | 有效值 | 描述                             |
| --------- | ------------- | ------ | ------ | ------ | -------------------------------- |
| byp​​ass_missing |boolean| 否 | false | | 如果为 true，则在缺少 `User-Agent` 标头时绕过用户代理限制检查。|
| allowlist | array[string] | 否 | | | 要允许的用户代理列表。支持正则表达式。应配置 `allowlist` 和 `denylist` 中至少一个，但不能同时配置。|
| denylist | array[string] | 否 | | | 要拒绝的用户代理列表。支持正则表达式。应配置 `allowlist` 和 `denylist` 中至少一个，但不能同时配置。|
| message | string | 否 | "Not allowed" | | 拒绝用户代理访问时返回的消息。|

## 示例

以下示例演示了如何针对不同场景配置 `ua-restriction`。

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### 拒绝网络爬虫并自定义错误消息

以下示例演示了如何配置插件以抵御不需要的网络爬虫并自定义拒绝消息。

创建路由并配置插件以使用自定义消息阻止特定爬虫访问资源：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "ua-restriction-route",
    "uri": "/anything",
    "plugins": {
      "ua-restriction": {
        "bypass_missing": false,
        "denylist": [
          "(Baiduspider)/(\\d+)\\.(\\d+)",
          "bad-bot-1"
        ],
        "message": "Access denied"
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

向路由发送请求：

```shell
curl -i "http://127.0.0.1:9080/anything"
```

您应该收到 `HTTP/1.1 200 OK` 响应。

使用不允许的用户代理向路由发送另一个请求：

```shell
curl -i "http://127.0.0.1:9080/anything" -H 'User-Agent: Baiduspider/5.0'
```

您应该收到 `HTTP/1.1 403 Forbidden` 响应，其中包含以下消息：

```text
{"message":"Access denied"}
```

### 绕过 UA 限制检查

以下示例说明如何配置插件以允许特定用户代理的请求绕过 UA 限制。

创建如下路由：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "ua-restriction-route",
    "uri": "/anything",
    "plugins": {
      "ua-restriction": {
        "bypass_missing": true,
        "allowlist": [
          "good-bot-1"
        ],
        "message": "Access denied"
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

向路由发送一个请求而不修改用户代理：

```shell
curl -i "http://127.0.0.1:9080/anything"
```

您应该收到一个 `HTTP/1.1 403 Forbidden` 响应，其中包含以下消息：

```text
{"message":"Access denied"}
```

向路由发送另一个请求，用户代理为空：

```shell
curl -i "http://127.0.0.1:9080/anything" -H 'User-Agent: '
```

您应该收到一个 `HTTP/1.1 200 OK` 响应。
