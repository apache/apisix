---
title: Plugin
keywords:
  - API Gateway
  - Apache APISIX
  - Plugin
  - Filter
  - Priority
description: This article introduces the related information of the APISIX Plugin object and how to use it, and introduces how to customize the plugin priority, customize the error response, and dynamically control the execution status of the plugin.
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

## Description

APISIX Plugins extend APISIX's functionalities to meet organization or user-specific requirements in traffic management, observability, security, request/response transformation, serverless computing, and more.

A **Plugin** configuration can be bound directly to a [`Route`](route.md), [`Service`](service.md), [`Consumer`](consumer.md) or [`Plugin Config`](plugin-config.md). You can refer to [Admin API plugins](../admin-api.md#plugin) for how to use this resource.

If existing APISIX Plugins do not meet your needs, you can also write your own plugins in Lua or other languages such as Java, Python, Go, and Wasm.

## Plugins installation

By default, most APISIX plugins are [installed](https://github.com/apache/apisix/blob/master/apisix/cli/config.lua):

```lua title="apisix/cli/config.lua"
local _M = {
  ...
  plugins = {
    "real-ip",
    "ai",
    "client-control",
    "proxy-control",
    "request-id",
    "zipkin",
    "ext-plugin-pre-req",
    "fault-injection",
    "mocking",
    "serverless-pre-function",
    ...
  },
  ...
}
```

If you would like to make adjustments to plugins installation, add the customized `plugins` configuration to `config.yaml`. For example:

```yaml
plugins:
  - real-ip                   # installed
  - ai
  - client-control
  - proxy-control
  - request-id
  - zipkin
  - ext-plugin-pre-req
  - fault-injection
  # - mocking                 # not install
  - serverless-pre-function
  ...                         # other plugins
```

See `config.yaml.example`(https://github.com/apache/apisix/blob/master/conf/config.yaml.example) for a complete configuration reference.

You should reload APISIX for configuration changes to take effect.

## Plugins execution lifecycle

An installed plugin is first initialized. The configuration of the plugin is then checked against the defined [JSON Schema](https://json-schema.org) to make sure the plugins configuration schema is correct.

When a request goes through APISIX, the plugin's corresponding methods are executed in one or more of the following phases : `rewrite`, `access`, `before_proxy`, `header_filter`, `body_filter`, and `log`. These phases are largely influenced by the [OpenResty directives](https://openresty-reference.readthedocs.io/en/latest/Directives/).

<br />
<div style={{textAlign: 'center'}}>
<img src="https://static.apiseven.com/uploads/2023/03/09/ZsH5C8Og_plugins-phases.png" alt="Routes Diagram" width="50%"/>
</div>
<br />

## Plugins execution order

In general, plugins are executed in the following order:

1. Plugins in [global rules](./global-rule.md)
   1. plugins in rewrite phase
   2. plugins in access phase

2. Plugins bound to other objects
   1. plugins in rewrite phase
   2. plugins in access phase

Within each phase, you can optionally define a new priority number in the `_meta.priority` field of the plugin, which takes precedence over the default plugins priority during execution. Plugins with higher priority numbers are executed first.

For example, if you want to have `limit-count` (priority 1002) run before `ip-restriction` (priority 3000) when requests hit a route, you can do so by passing a higher priority number to `_meta.priority` field of `limit-count`:

```json
{
  ...,
  "plugins": {
    "limit-count": {
      ...,
      "_meta": {
        "priority": 3010
      }
    }
  }
}
```

To reset the priority of this plugin instance to the default, simply remove the `_meta.priority` field from your plugin configuration.

## Plugins merging precedence

When the same plugin is configured both globally in a global rule and locally in an object (e.g. a route), both plugin instances are executed sequentially.

However, if the same plugin is configured locally on multiple objects, such as on [Route](./route.md), [Service](./service.md), [Consumer](./consumer.md), [Consumer Group](./consumer-group.md), or [Plugin Config](./plugin-config.md), only one copy of configuration is used as each non-global plugin is only executed once. This is because during execution, plugins configured in these objects are merged with respect to a specific order of precedence:

`Consumer`  > `Consumer Group` > `Route` > `Plugin Config` > `Service`

such that if the same plugin has different configurations in different objects, the plugin configuration with the highest order of precedence during merging will be used.

## Plugin common configuration

Some common configurations can be applied to plugins through the `_meta` configuration items, the specific configuration items are as follows:

| Name           | Type           | Description |
|----------------|--------------- |-------------|
| disable        | boolean        | When set to `true`, the plugin is disabled. |
| error_response | string/object  | Custom error response. |
| priority       | integer        | Custom plugin priority. |
| filter         | array          | Depending on the requested parameters, it is decided at runtime whether the plugin should be executed. Something like this: `{{var, operator, val}, {var, operator, val}, ...}}`. For example: `{"arg_version", "==", "v2"}`, indicating that the current request parameter `version` is `v2`. The variables here are consistent with NGINX internal variables. For details on supported operators, please see [lua-resty-expr](https://github.com/api7/lua-resty-expr#operator-list). |

### Disable the plugin

Through the `disable` configuration, you can add a new plugin with disabled status and the request will not go through the plugin.

```json
{
    "proxy-rewrite": {
        "_meta": {
            "disable": true
        }
    }
}
```

### Custom error response

Through the `error_response` configuration, you can configure the error response of any plugin to a fixed value to avoid troubles caused by the built-in error response information of the plugin.

The configuration below means to customize the error response of the `jwt-auth` plugin to `Missing credential in request`.

```json
{
    "jwt-auth": {
        "_meta": {
            "error_response": {
                "message": "Missing credential in request"
            }
        }
    }
}
```

### Custom plugin priority

All plugins have default priorities, but through the `priority` configuration item you can customize the plugin priority and change the plugin execution order.

```json
 {
    "serverless-post-function": {
        "_meta": {
            "priority": 10000
        },
        "phase": "rewrite",
        "functions" : ["return function(conf, ctx)
                    ngx.say(\"serverless-post-function\");
                    end"]
    },
    "serverless-pre-function": {
        "_meta": {
            "priority": -2000
        },
        "phase": "rewrite",
        "functions": ["return function(conf, ctx)
                    ngx.say(\"serverless-pre-function\");
                    end"]
    }
}
```

The default priority of serverless-pre-function is 10000, and the default priority of serverless-post-function is -2000. By default, the serverless-pre-function plugin will be executed first, and serverless-post-function plugin will be executed next.

The above configuration means setting the priority of the serverless-pre-function plugin to -2000 and the priority of the serverless-post-function plugin to 10000. The serverless-post-function plugin will be executed first, and serverless-pre-function plugin will be executed next.

:::note

- Custom plugin priority only affects the current object(route, service ...) of the plugin instance binding, not all instances of that plugin. For example, if the above plugin configuration belongs to Route A, the order of execution of the plugins serverless-post-function and serverless-post-function on Route B will not be affected and the default priority will be used.
- Custom plugin priority does not apply to the rewrite phase of some plugins configured on the consumer. The rewrite phase of plugins configured on the route will be executed first, and then the rewrite phase of plugins (exclude auth plugins) from the consumer will be executed.

:::

### Dynamically control whether the plugin is executed

By default, all plugins specified in the route will be executed. But we can add a filter to the plugin through the `filter` configuration item, and control whether the plugin is executed through the execution result of the filter.

The configuration below means that the `proxy-rewrite` plugin will only be executed if the `version` value in the request query parameters is `v2`.

```json
{
    "proxy-rewrite": {
        "_meta": {
            "filter": [
                ["arg_version", "==", "v2"]
            ]
        },
        "uri": "/anything"
    }
}
```

Create a complete route with the below configuration:

```json
{
    "uri": "/get",
    "plugins": {
        "proxy-rewrite": {
            "_meta": {
                "filter": [
                    ["arg_version", "==", "v2"]
                ]
            },
            "uri": "/anything"
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "httpbin.org:80": 1
        }
    }
}
```

When the request does not have any parameters, the `proxy-rewrite` plugin will not be executed, the request will be proxy to the upstream `/get`:

```shell
curl -v /dev/null http://127.0.0.1:9080/get -H"host:httpbin.org"
```

```shell
< HTTP/1.1 200 OK
......
< Server: APISIX/2.15.0
<
{
  "args": {},
  "headers": {
    "Accept": "*/*",
    "Host": "httpbin.org",
    "User-Agent": "curl/7.79.1",
    "X-Amzn-Trace-Id": "Root=1-62eb6eec-46c97e8a5d95141e621e07fe",
    "X-Forwarded-Host": "httpbin.org"
  },
  "origin": "127.0.0.1, 117.152.66.200",
  "url": "http://httpbin.org/get"
}
```

When the parameter `version=v2` is carried in the request, the `proxy-rewrite` plugin is executed, and the request will be proxy to the upstream `/anything`:

```shell
curl -v /dev/null http://127.0.0.1:9080/get?version=v2 -H"host:httpbin.org"
```

```shell
< HTTP/1.1 200 OK
......
< Server: APISIX/2.15.0
<
{
  "args": {
    "version": "v2"
  },
  "data": "",
  "files": {},
  "form": {},
  "headers": {
    "Accept": "*/*",
    "Host": "httpbin.org",
    "User-Agent": "curl/7.79.1",
    "X-Amzn-Trace-Id": "Root=1-62eb6f02-24a613b57b6587a076ef18b4",
    "X-Forwarded-Host": "httpbin.org"
  },
  "json": null,
  "method": "GET",
  "origin": "127.0.0.1, 117.152.66.200",
  "url": "http://httpbin.org/anything?version=v2"
}
```

## Hot reload

APISIX Plugins are hot-loaded. This means that there is no need to restart the service if you add, delete, modify plugins, or even if you update the plugin code. To hot-reload, you can send an HTTP request through the [Admin API](../admin-api.md):

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/plugins/reload -H "X-API-KEY: $admin_key" -X PUT
```

:::note

If a configured Plugin is disabled, then its execution will be skipped.

:::

### Hot reload in standalone mode

For hot-reloading in standalone mode, see the plugin related section in [stand alone mode](../deployment-modes.md#standalone).
