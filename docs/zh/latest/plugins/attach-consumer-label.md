---
title: attach-consumer-label
keywords:
  - Apache APISIX
  - API 网关
  - API Consumer
description: 本文介绍了 Apache APISIX attach-consumer-label 插件的相关操作，你可以使用此插件向上游服务传递自定义的 Consumer labels。
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

`attach-consumer-label` 插件在 X-Consumer-Username 和 X-Credential-Indentifier 之外，还将自定义的消费者相关标签附加到经过身份验证的请求，以便上游服务区分消费者并实现额外的逻辑。

## 属性

| 名称      | 类型   | 必选项  | 默认值    | 有效值    | 描述                                                                                                                                                 |
|----------|--------|--------|----------|--------|----------------------------------------------------------------------------------------------------------------------------------------------------|
| headers  | object | 是     |          |        | 要附加到请求标头的 Consumer 标签的键值对，其中键是请求标头名称，例如 "X-Consumer-Role"，值是对客户标签键的引用，例如 "$role"。请注意，该值应始终以美元符号 (`$`) 开头。如果 Consumer 上没有配置引用的值，则相应的标头将不会附加到请求中。 |

## 启用插件

下面的示例演示了如何在通过身份验证的请求转发到上游服务之前，将自定义标签附加到请求标头。如果请求被拒绝，就不会在请求标头上附加任何消费者标签。如果某个标签值未在消费者上配置，但在“attach-consumer-label”插件中被引用，相应的标头也不会被附加。

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

创建一个有自定义标签的 Consumer `john`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "username": "john",
    "labels": {
      "department": "devops",
      "company": "api7"
    }
  }'
```

为 Consumer `john` 配置 `key-auth`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/john/credentials" -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "id": "cred-john-key-auth",
    "plugins": {
      "key-auth": {
        "key": "john-key"
      }
    }
  }'
```

创建路由并启用 `key-auth` 和 `attach-consumer-label` 插件：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "id": "attach-consumer-label-route",
    "uri": "/get",
    "plugins": {
      "key-auth": {},
      "attach-consumer-label": {
        "headers": {
          "X-Consumer-Department": "$department",
          "X-Consumer-Company": "$company",
          "X-Consumer-Role": "$role"
        }
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

:::tip

引用标签的值必须以 `$` 符号开头。

:::

使用正确的 apikey 请求该路由，验证插件：

```shell
curl -i "http://127.0.0.1:9080/get" -H 'apikey: john-key'
```

可以看到类似的 `HTTP/1.1 200 OK` 响应：

```text
{
  "args": {},
  "headers": {
    "Accept": "*/*",
    "Apikey": "john-key",
    "Host": "127.0.0.1",
    "X-Consumer-Username": "john",
    "X-Credential-Indentifier": "cred-john-key-auth",
    "X-Consumer-Company": "api7",
    "X-Consumer-Department": "devops",
    "User-Agent": "curl/8.6.0",
    "X-Amzn-Trace-Id": "Root=1-66e5107c-5bb3e24f2de5baf733aec1cc",
    "X-Forwarded-Host": "127.0.0.1"
  },
  "origin": "192.168.65.1, 205.198.122.37",
  "url": "http://127.0.0.1/get"
}
```

## 删除插件

当你需要禁用该插件时，可以通过以下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/attach-consumer-label-route" -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "uri": "/get",
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```
