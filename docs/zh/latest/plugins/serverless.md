---
title: serverless
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - Serverless
description: serverless-pre-function 和 serverless-post-function 插件支持在 APISIX 的指定阶段动态运行 Lua 函数。
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
  <link rel="canonical" href="https://docs.api7.ai/hub/serverless-functions" />
</head>

## 描述

无服务器函数由两个插件组成：`serverless-pre-function` 和 `serverless-post-function`。这些插件支持在[执行阶段](../terminology/plugin.md#plugins-execution-lifecycle)的开始和结束时执行用户定义的逻辑。

## 属性

| 名称      | 类型          | 必选项 | 默认值   | 有效值                                                                       | 描述                                                                            |
| --------- | ------------- | ----- | -------- | ---------------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| phase     | string        | 否    | "access" | ["rewrite", "access", "header_filter", "body_filter", "log", "before_proxy"] | 执行 serverless 函数之前或之后的阶段。                                           |
| functions | array[string] | 是    |          |                                                                              | 按顺序执行的函数列表。                                                          |

## 编写函数的提示

serverless 插件中只允许使用 Lua 函数，不允许使用其他 Lua 代码。

例如，匿名函数是合法的：

```lua
return function()
    ngx.log(ngx.ERR, 'one')
end
```

闭包也是合法的：

```lua
local count = 1
return function()
    count = count + 1
    ngx.say(count)
end
```

但不是函数类型的代码就是非法的：

```lua
local count = 1
ngx.say(count)
```

## 示例

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

以下示例演示如何在不同场景中配置 `serverless-pre-function` 和 `serverless-post-function` 插件。

### 在阶段前后记录信息

以下示例演示如何配置 serverless 插件，在 `rewrite` [阶段](../terminology/plugin.md#plugins-execution-lifecycle)之前和之后执行自定义逻辑，将信息记录到错误日志中。

创建如下路由：

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "serverless-pre-route",
    "uri": "/anything",
    "plugins": {
      "serverless-pre-function": {
        "phase": "rewrite",
        "functions" : [
          "return function() ngx.log(ngx.ERR, \"serverless pre function\"); end"
        ]
      },
      "serverless-post-function": {
        "phase": "rewrite",
        "functions" : [
          "return function(conf, ctx) ngx.log(ngx.ERR, \"match uri \", ctx.curr_req_matched and ctx.curr_req_matched._path); end"
        ]
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

- 将 serverless pre-function 逻辑挂钩到 `rewrite` [阶段](../terminology/plugin.md#plugins-execution-lifecycle)。

- 定义一个 Lua 函数，在错误日志中记录 `serverless pre function` 消息。

- 将 serverless post-function 逻辑挂钩到 `rewrite` [阶段](../terminology/plugin.md#plugins-execution-lifecycle)。

- 定义一个 Lua 函数，在错误日志中记录匹配的 URI。`conf` 和 `ctx` 可以像其他插件一样作为前两个参数传递，其中 `conf` 是插件配置，`ctx` 是请求上下文。

</TabItem>

<TabItem value="adc">

```yaml title="adc.yaml"
services:
  - name: httpbin
    routes:
      - name: serverless-pre-route
        uris:
          - /anything
        plugins:
          serverless-pre-function:
            phase: rewrite
            functions:
              - |
                return function()
                  ngx.log(ngx.ERR, "serverless pre function")
                end
          serverless-post-function:
            phase: rewrite
            functions:
              - |
                return function(conf, ctx)
                  ngx.log(ngx.ERR, "match uri ", ctx.curr_req_matched and ctx.curr_req_matched._path)
                end
    upstream:
      type: roundrobin
      nodes:
        - host: httpbin.org
          port: 80
          weight: 1
```

同步配置到网关：

```shell
adc sync -f adc.yaml
```

</TabItem>

<TabItem value="aic">

<Tabs
groupId="k8s-api"
defaultValue="gateway-api"
values={[
{label: 'Gateway API', value: 'gateway-api'},
{label: 'APISIX CRD', value: 'apisix-crd'}
]}>

<TabItem value="gateway-api">

```yaml title="serverless-functions-ic.yaml"
apiVersion: v1
kind: Service
metadata:
  namespace: aic
  name: httpbin-external-domain
spec:
  type: ExternalName
  externalName: httpbin.org
---
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  namespace: aic
  name: serverless-functions-plugin-config
spec:
  plugins:
    - name: serverless-pre-function
      config:
        phase: rewrite
        functions:
          - |
            return function()
              ngx.log(ngx.ERR, "serverless pre function")
            end
    - name: serverless-post-function
      config:
        phase: rewrite
        functions:
          - |
            return function(conf, ctx)
              ngx.log(ngx.ERR, "match uri ", ctx.curr_req_matched and ctx.curr_req_matched._path)
            end
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: serverless-pre-route
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: Exact
            value: /anything
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: serverless-functions-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

</TabItem>

<TabItem value="apisix-crd">

```yaml title="serverless-functions-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixUpstream
metadata:
  namespace: aic
  name: httpbin-external-domain
spec:
  ingressClassName: apisix
  externalNodes:
  - type: Domain
    name: httpbin.org
---
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: serverless-pre-route
spec:
  ingressClassName: apisix
  http:
    - name: serverless-pre-route
      match:
        paths:
          - /anything
      upstreams:
        - name: httpbin-external-domain
      plugins:
        - name: serverless-pre-function
          config:
            phase: rewrite
            functions:
              - |
                return function()
                  ngx.log(ngx.ERR, "serverless pre function")
                end
        - name: serverless-post-function
          config:
            phase: rewrite
            functions:
              - |
                return function(conf, ctx)
                  ngx.log(ngx.ERR, "match uri ", ctx.curr_req_matched and ctx.curr_req_matched._path)
                end
```

</TabItem>

</Tabs>

应用配置：

```shell
kubectl apply -f serverless-functions-ic.yaml
```

</TabItem>

</Tabs>

向路由发送请求：

```shell
curl -i "http://127.0.0.1:9080/anything"
```

你应该会收到 `HTTP/1.1 200 OK` 响应，并在错误日志中看到以下条目：

```text
2024/05/09 15:07:09 [error] 51#51: *3963 [lua] [string "return function() ngx.log(ngx.ERR, "serverles..."]:1: func(): serverless pre function, client: 172.21.0.1, server: _, request: "GET /anything HTTP/1.1", host: "127.0.0.1:9080"
2024/05/09 15:16:58 [error] 50#50: *9343 [lua] [string "return function(conf, ctx) ngx.log(ngx.ERR, "..."]:1: func(): match uri /anything, client: 172.21.0.1, server: _, request: "GET /anything HTTP/1.1", host: "127.0.0.1:9080"
```

第一条记录由 pre-function 添加，第二条记录由 post-function 添加。
