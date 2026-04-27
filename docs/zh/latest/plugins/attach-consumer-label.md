---
title: attach-consumer-label
keywords:
  - Apache APISIX
  - API 网关
  - 插件
  - attach-consumer-label
  - Consumer
description: attach-consumer-label 插件将自定义消费者标签附加到经过身份验证的请求，以便上游服务实现额外的业务逻辑。
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
   <link rel="canonical" href="https://docs.api7.ai/hub/attach-consumer-label" />
 </head>

## 描述

`attach-consumer-label` 插件在 `X-Consumer-Username` 和 `X-Credential-Identifier` 之外，还将自定义的消费者相关标签附加到经过身份验证的请求，以便上游服务区分消费者并实现额外的业务逻辑。

## 属性

| 名称      | 类型   | 必选项 | 默认值 | 有效值 | 描述                                                                                                                                                 |
|----------|--------|--------|--------|--------|----------------------------------------------------------------------------------------------------------------------------------------------------|
| headers  | object | 是     |        |        | 要附加到请求标头的消费者标签键值对，其中键是请求标头名称（例如 `X-Consumer-Role`），值是对消费者标签键的引用（例如 `$role`）。注意，值必须以美元符号（`$`）开头。如果消费者上未配置被引用的标签，则对应的请求标头将不会被附加。 |

## 示例

下面的示例演示了如何在经过身份验证的请求转发到上游服务之前，将自定义标签附加到请求标头。如果请求被拒绝，则不会在请求标头中附加任何消费者标签。如果某个标签值未在消费者上配置但在 `attach-consumer-label` 插件中被引用，对应的请求标头也不会被附加。

:::note

你可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### 附加消费者标签

创建一个带有自定义标签的消费者 `john`：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "john",
    "labels": {
      "department": "devops",
      "company": "api7"
    }
  }'
```

为消费者 `john` 配置 `key-auth` 凭据：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/john/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
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
  -H "X-API-KEY: ${admin_key}" \
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

- `X-Consumer-Department`：附加消费者的 `department` 标签值。
- `X-Consumer-Company`：附加消费者的 `company` 标签值。
- `X-Consumer-Role`：附加消费者的 `role` 标签值。由于消费者上未配置 `role` 标签，预期该标头不会出现在转发到上游服务的请求中。

:::tip

引用消费者标签的值必须以 `$` 符号开头。

:::

向路由发送带有正确凭据的请求，进行验证：

```shell
curl -i "http://127.0.0.1:9080/get" -H 'apikey: john-key'
```

你应该看到类似如下的 `HTTP/1.1 200 OK` 响应：

```json
{
  "args": {},
  "headers": {
    "Accept": "*/*",
    "Apikey": "john-key",
    "Host": "127.0.0.1",
    "X-Consumer-Username": "john",
    "X-Credential-Identifier": "cred-john-key-auth",
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

注意，由于消费者上未配置 `role` 标签，响应中不包含 `X-Consumer-Role` 标头。
