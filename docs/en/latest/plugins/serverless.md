---
title: Serverless Functions (serverless)
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - Serverless
description: The serverless plugins, `serverless-pre-function` and `serverless-post-function`, allow you to dynamically run Lua functions at specified phases in APISIX.
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

## Description

The serverless functions consist of two plugins, `serverless-pre-function` and `serverless-post-function`. These plugins enable the execution of user-defined logic at the beginning and end of the [execution phases](../terminology/plugin.md#plugins-execution-lifecycle) the functions hook to.

## Attributes

| Name      | Type          | Required | Default  | Valid values                                                                 | Description                                                      |
|-----------|---------------|----------|----------|------------------------------------------------------------------------------|------------------------------------------------------------------|
| phase     | string        | False    | "access" | ["rewrite", "access", "header_filter", "body_filter", "log", "before_proxy"] | Phase before or after which the serverless function is executed. |
| functions | array[string] | True     |          |                                                                              | List of functions that are executed sequentially.                |

## Tips for Writing Functions

Only Lua functions are allowed in the serverless plugins and not other Lua code.

For example, anonymous functions are legal:

```lua
return function()
    ngx.log(ngx.ERR, 'one')
end
```

Closures are also legal:

```lua
local count = 1
return function()
    count = count + 1
    ngx.say(count)
end
```

But code other than functions are illegal:

```lua
local count = 1
ngx.say(count)
```

## Examples

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

The examples below demonstrate how you can configure the `serverless-pre-function` and `serverless-post-function` plugins for different scenarios.

### Log Information before and after a Phase

The example below demonstrates how you can configure the serverless plugins to execute custom logics to log information to error logs before and after the `rewrite` [phase](../terminology/plugin.md#plugins-execution-lifecycle).

Create a Route as such:

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

Synchronize the configuration to the gateway:

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

Apply the configuration:

```shell
kubectl apply -f serverless-functions-ic.yaml
```

</TabItem>

</Tabs>

Send the request to the Route:

```shell
curl -i "http://127.0.0.1:9080/anything"
```

You should receive an `HTTP/1.1 200 OK` response and see the following entries in the error log:

```text
2024/05/09 15:07:09 [error] 51#51: *3963 [lua] [string "return function() ngx.log(ngx.ERR, "serverles..."]:1: func(): serverless pre function, client: 172.21.0.1, server: _, request: "GET /anything HTTP/1.1", host: "127.0.0.1:9080"
2024/05/09 15:16:58 [error] 50#50: *9343 [lua] [string "return function(conf, ctx) ngx.log(ngx.ERR, "..."]:1: func(): match uri /anything, client: 172.21.0.1, server: _, request: "GET /anything HTTP/1.1", host: "127.0.0.1:9080"
```

The first entry is added by the pre-function and the second entry is added by the post-function.

### Register Custom Variables

The example below demonstrates how you can register custom built-in variables using the serverless plugins and use the newly created variable in logs.

:::info

This example cannot be completed with the Ingress Controller because it does not support configuring Route labels.

:::

Start an example rsyslog server:

```shell
docker run -d -p 514:514 --name example-rsyslog-server rsyslog/syslog_appliance_alpine
```

Create a [Service](../terminology/service.md) with a serverless function to register a custom variable `a6_route_labels`, enable a logging plugin to later log the custom variable, and configure an upstream:

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'}
]}>

<TabItem value="admin-api">

```shell
curl "http://127.0.0.1:9180/apisix/admin/services" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id":"srv_custom_var",
    "plugins": {
      "serverless-pre-function": {
        "phase": "rewrite",
        "functions": [
          "return function() local core = require \"apisix.core\" core.ctx.register_var(\"a6_route_labels\", function(ctx) local route = ctx.matched_route and ctx.matched_route.value if route and route.labels then return route.labels end return nil end); end"
        ]
      },
      "syslog": {
        "host" : "172.0.0.1",
        "port" : 514,
        "flush_limit" : 1
      }
    },
    "upstream": {
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```

</TabItem>

<TabItem value="adc">

```yaml title="adc.yaml"
services:
  - name: srv-custom-var
    plugins:
      serverless-pre-function:
        phase: rewrite
        functions:
          - |
            return function()
              local core = require("apisix.core")
              core.ctx.register_var("a6_route_labels", function(ctx)
                local route = ctx.matched_route and ctx.matched_route.value
                if route and route.labels then
                  return route.labels
                end
                return nil
              end)
            end
      syslog:
        host: 172.0.0.1
        port: 514
        flush_limit: 1
    upstream:
      nodes:
        - host: httpbin.org
          port: 80
          weight: 1
```

Synchronize the configuration to the gateway:

```shell
adc sync -f adc.yaml
```

</TabItem>

</Tabs>

Next, update the log format for all `syslog` instances with the new variable by configuring the [Plugin metadata](../terminology/plugin.md#plugin-metadata):

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'}
]}>

<TabItem value="admin-api">

```shell
curl "http://127.0.0.1:9180/apisix/admin/plugin_metadata/syslog" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "log_format": {
      "host": "$host",
      "client_ip": "$remote_addr",
      "labels": "$a6_route_labels"
    }
  }'
```

</TabItem>

<TabItem value="adc">

```yaml title="adc.yaml"
plugin_metadata:
  syslog:
    log_format:
      host: "$host"
      client_ip: "$remote_addr"
      labels: "$a6_route_labels"
```

Synchronize the configuration to the gateway:

```shell
adc sync -f adc.yaml
```

</TabItem>

</Tabs>

Finally, create a Route:

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'}
]}>

<TabItem value="admin-api">

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id":"route_custom_var",
    "uri":"/get",
    "service_id": "srv_custom_var",
    "labels": {
      "key": "test_a6_route_labels"
    }
}'
```

</TabItem>

<TabItem value="adc">

```yaml title="adc.yaml"
# Other Configs
services:
  - name: srv-custom-var
    routes:
      - name: route-custom-var
        uris:
          - /get
        labels:
          key: test_a6_route_labels
```

Synchronize the configuration to the gateway:

```shell
adc sync -f adc.yaml
```

</TabItem>

</Tabs>

To verify the variable registration, send a request to the Route:

```shell
curl "http://127.0.0.1:9080/get"
```

You should see a log entry in your syslog server similar to the following:

```json
{
  "host":"127.0.0.1",
  "route_id":"route_custom_var",
  "client_ip":"172.19.0.1",
  "labels":{
    "key":"test_a6_route_labels"
  },
  "service_id":"srv_custom_var"
}
```

This verifies the custom variable was registered and it logs the `labels` information in a Route successfully.

### Modify a Specific Field in Response Body

The example below demonstrates how you can use the serverless plugins to remove a specific field from a JSON response body.

Before proceeding with the removal, first configure a Route as follows to see the unmodified response:

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
    "id":"serverless-remove-body-info",
    "uri": "/get",
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```

</TabItem>

<TabItem value="adc">

```yaml title="adc.yaml"
services:
  - name: httpbin
    routes:
      - name: serverless-remove-body-info
        uris:
          - /get
    upstream:
      type: roundrobin
      nodes:
        - host: httpbin.org
          port: 80
          weight: 1
```

Synchronize the configuration to the gateway:

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

```yaml title="serverless-remove-body-ic.yaml"
apiVersion: v1
kind: Service
metadata:
  namespace: aic
  name: httpbin-external-domain
spec:
  type: ExternalName
  externalName: httpbin.org
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: serverless-remove-body-info
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: Exact
            value: /get
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

</TabItem>

<TabItem value="apisix-crd">

```yaml title="serverless-remove-body-ic.yaml"
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
  name: serverless-remove-body-info
spec:
  ingressClassName: apisix
  http:
    - name: serverless-remove-body-info
      match:
        paths:
          - /get
      upstreams:
        - name: httpbin-external-domain
```

</TabItem>

</Tabs>

Apply the configuration:

```shell
kubectl apply -f serverless-remove-body-ic.yaml
```

</TabItem>

</Tabs>

Send a request to the Route:

```shell
curl "http://127.0.0.1:9080/get"
```

You should see a response similar to the following with your host and proxy's IP information:

```json
{
  "args": {},
  "headers": {
    "Accept": "*/*",
    "Host": "127.0.0.1",
    "User-Agent": "curl/8.4.0",
    "X-Amzn-Trace-Id": "Root=1-663db30f-51448a1b635f2f4338a4fcfc",
    "X-Forwarded-Host": "127.0.0.1"
  },
  "origin": "172.19.0.1, 43.252.208.84",
  "url": "http://127.0.0.1/get"
}
```

To remove the `origin` field from the response, update the Route with serverless plugins:

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
curl "http://127.0.0.1:9180/apisix/admin/routes/serverless-remove-body-info" -X PATCH \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "plugins": {
      "serverless-pre-function": {
        "phase": "header_filter",
        "functions" : [
          "return function(conf, ctx)
            local core = require(\"apisix.core\")
            core.response.clear_header_as_body_modified()
          end"
        ]
      },
      "serverless-post-function": {
        "phase": "body_filter",
        "functions" : [
          "return function(conf, ctx) local cjson = require(\"cjson\") local core = require(\"apisix.core\") local body = core.response.hold_body_chunk(ctx) if not body then return end body = cjson.decode(body) body.origin = nil body = cjson.encode(body) ngx.arg[1] = body end"
        ]
      }
    }
  }'
```

</TabItem>

<TabItem value="adc">

```yaml title="adc.yaml"
services:
  - name: httpbin
    routes:
      - name: serverless-remove-body-info
        uris:
          - /get
        plugins:
          serverless-pre-function:
            phase: header_filter
            functions:
              - |
                return function(conf, ctx)
                  local core = require("apisix.core")
                  core.response.clear_header_as_body_modified()
                end
          serverless-post-function:
            phase: body_filter
            functions:
              - |
                return function(conf, ctx)
                  local cjson = require("cjson")
                  local core = require("apisix.core")
                  local body = core.response.hold_body_chunk(ctx)
                  if not body then
                    return
                  end
                  body = cjson.decode(body)
                  body.origin = nil
                  body = cjson.encode(body)
                  ngx.arg[1] = body
                end
    upstream:
      type: roundrobin
      nodes:
        - host: httpbin.org
          port: 80
          weight: 1
```

Synchronize the configuration to the gateway:

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

```yaml title="serverless-remove-body-ic.yaml"
# Other Configs
# ---
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  namespace: aic
  name: serverless-remove-body-plugin-config
spec:
  plugins:
    - name: serverless-pre-function
      config:
        phase: header_filter
        functions:
          - |
            return function(conf, ctx)
              local core = require("apisix.core")
              core.response.clear_header_as_body_modified()
            end
    - name: serverless-post-function
      config:
        phase: body_filter
        functions:
          - |
            return function(conf, ctx)
              local cjson = require("cjson")
              local core = require("apisix.core")
              local body = core.response.hold_body_chunk(ctx)
              if not body then
                return
              end
              body = cjson.decode(body)
              body.origin = nil
              body = cjson.encode(body)
              ngx.arg[1] = body
            end
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: serverless-remove-body-info
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: Exact
            value: /get
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: serverless-remove-body-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

</TabItem>

<TabItem value="apisix-crd">

```yaml title="serverless-remove-body-ic.yaml"
# Other Configs
# ---
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: serverless-remove-body-info
spec:
  ingressClassName: apisix
  http:
    - name: serverless-remove-body-info
      match:
        paths:
          - /get
      upstreams:
        - name: httpbin-external-domain
      plugins:
        - name: serverless-pre-function
          config:
            phase: header_filter
            functions:
              - |
                return function(conf, ctx)
                  local core = require("apisix.core")
                  core.response.clear_header_as_body_modified()
                end
        - name: serverless-post-function
          config:
            phase: body_filter
            functions:
              - |
                return function(conf, ctx)
                  local cjson = require("cjson")
                  local core = require("apisix.core")
                  local body = core.response.hold_body_chunk(ctx)
                  if not body then
                    return
                  end
                  body = cjson.decode(body)
                  body.origin = nil
                  body = cjson.encode(body)
                  ngx.arg[1] = body
                end
```

</TabItem>

</Tabs>

Apply the configuration:

```shell
kubectl apply -f serverless-remove-body-ic.yaml
```

</TabItem>

</Tabs>

The pre-function calls `clear_header_as_body_modified` to clear body-related response headers such as `Content-Length`. The post-function collects the response body with `hold_body_chunk`, decodes the JSON payload, removes the `origin` field, and writes the updated body back to the response.

Send another request to the Route:

```shell
curl "http://127.0.0.1:9080/get"
```

You should see a response without the `origin` information:

```json
{
  "url":"http://127.0.0.1/get",
  "args":{},
  "headers":{
    "X-Forwarded-Host":"127.0.0.1",
    "Host":"127.0.0.1",
    "Accept":"*/*",
    "User-Agent":"curl/8.4.0",
    "X-Amzn-Trace-Id":"Root=1-663db276-1c15276864294d963c6e1755"
  }
}
```

For simpler response modifications, such as modifying HTTP status codes, request headers, or the entire response body, please use the [`response-rewrite`](./response-rewrite.md) plugin.
