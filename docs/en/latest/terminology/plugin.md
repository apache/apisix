---
title: Plugin
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

This represents the configuration of the plugins that are executed during the HTTP request/response lifecycle. A **Plugin** configuration can be bound directly to a [`Route`](./route.md), a [`Service`](./service.md), a [`Consumer`](./consumer.md) or a [`Plugin Config`](./plugin-config.md).

:::note

While configuring the same plugin, only one copy of the configuration is valid. The order of precedence is always `Consumer` > `Route` > `Plugin Config` > `Service`.

:::

While [configuring APISIX](./architecture-design/apisix.md#configuring-apisix), you can declare the Plugins that are supported by the local APISIX node. This acts as a whitelisting mechanism as Plugins that are not in this whitelist will be automatically ignored. So, this feature can be used to temporarily turn off/turn on specific plugins.

## Adding a Plugin

For adding new plugins based on existing plugins, copy the data in the `plugins` node from the default configuration file `conf/config-default.yaml` to your configuration file (`conf/config.yaml`).

In a request, a Plugin is only executed once. This is true even if it is bound to multiple different objects like Routes and Services. The order in which Plugins are run is determined by its configured priorities:

```lua
local _M = {
    version = 0.1,
    priority = 0, -- the priority of this plugin will be 0
    name = plugin_name,
    schema = schema,
    metadata_schema = metadata_schema,
}
```

A Plugin configuration is submitted as part of the Route or Service and is placed under `plugins`. It internally uses the Plugin name as the hash key to holding the configuration items for the different Plugins.

```json
{
    ...
    "plugins": {
        "limit-count": {
            "count": 2,
            "time_window": 60,
            "rejected_code": 503,
            "key": "remote_addr"
        },
        "prometheus": {}
    }
}
```

Not all Plugins have specific configuration items (for example, [prometheus](/docs/apisix/plugins/prometheus/)). In such cases, an empty object identifier can be used.

A warning level log as shown below indicates that the request was rejected by the Plugin.

```shell
ip-restriction exits with http status code 403
```

## Plugin common configuration

Some common configurations can be applied to plugins through the `_meta` configuration items, the specific configuration items are as follows:

| Name         | Type | Description |
|--------------|------|-------------|
| disable      | boolean  | Whether to disable the plugin |
| error_response | string/object  | Custom error response |
| priority       | integer        | Custom plugin priority |
| filter  | array | Depending on the requested parameters, it is decided at runtime whether the plugin should be executed. Something like this: `{{var, operator, val}, {var, operator, val}, ...}}`. For example: `{"arg_version", "==", "v2"}`, indicating that the current request parameter `version` is `v2`. The variables here are consistent with NGINX internal variables. For details on supported operators, please see [lua-resty-expr](https://github.com/api7/lua-resty-expr#operator-list). |

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

The configuration below means to customize the error response of the `jwt-auth` plugin to '{"message": "Missing credential in request"}'.

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

```shell
curl http://127.0.0.1:9180/apisix/admin/plugins/reload -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT
```

:::note

If a configured Plugin is disabled, then its execution will be skipped.

### Hot reload in stand-alone mode

For hot-reloading in stand-alone mode, see the plugin related section in [stand alone mode](../stand-alone.md).
