---
title: Wasm
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

APISIX supports Wasm plugins written with [Proxy Wasm SDK](https://github.com/proxy-wasm/spec#sdks).

Currently, only a few APIs are implemented. Please follow [wasm-nginx-module](https://github.com/api7/wasm-nginx-module) to know the progress.

## Programming model

The plugin supports the following concepts from Proxy Wasm:

```
                    Wasm Virtual Machine
┌────────────────────────────────────────────────────────────────┐
│      Your Plugin                                               │
│          │                                                     │
│          │ 1: 1                                                │
│          │         1: N                                        │
│      VMContext  ──────────  PluginContext                      │
│                                           ╲ 1: N               │
│                                            ╲                   │
│                                             ╲  HttpContext     │
│                                               (Http stream)    │
└────────────────────────────────────────────────────────────────┘
```

* All plugins run in the same Wasm VM, like the Lua plugin in the Lua VM
* Each plugin has its own VMContext (the root ctx)
* Each configured route/global rules has its own PluginContext (the plugin ctx).
For example, if we have a service configuring with Wasm plugin, and two routes inherit from it,
there will be two plugin ctxs.
* Each HTTP request which hits the configuration will have its own HttpContext (the HTTP ctx).
For example, if we configure both global rules and route, the HTTP request will
have two HTTP ctxs, one for the plugin ctx from global rules and the other for the
plugin ctx from route.

## How to use

First of all, we need to define the plugin in `config.yaml`:

```yaml
wasm:
  plugins:
    - name: wasm_log # the name of the plugin
      priority: 7999 # priority
      file: t/wasm/log/main.go.wasm # the path of `.wasm` file
      http_request_phase: access # default to "access", can be one of ["access", "rewrite"]
```

That's all. Now you can use the wasm plugin as a regular plugin.

For example, enable this plugin on the specified route:

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl -i http://127.0.0.1:9180/apisix/admin/routes/1  -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/index.html",
    "plugins": {
         "wasm_log": {
             "conf": "blahblah"
         }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```

Attributes below can be configured in the plugin:

| Name           | Type                 | Requirement | Default        | Valid                                                                      | Description                                                                                                                                         |
| --------------------------------------| ------------| -------------- | -------- | --------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
|  conf         | string or object | required |   |  != "" and != {}     | the plugin ctx configuration which can be fetched via Proxy Wasm SDK |

Here is the mapping between Proxy Wasm callbacks and APISIX's phases:

* `proxy_on_configure`: run once there is not PluginContext for the new configuration.
For example, when the first request hits the route which has Wasm plugin configured.
* `proxy_on_http_request_headers`: run in the access/rewrite phase, depends on the configuration of `http_request_phase`.
* `proxy_on_http_request_body`: run in the same phase of `proxy_on_http_request_headers`. To run this callback, we need to set property `wasm_process_req_body` to non-empty value in `proxy_on_http_request_headers`. See `t/wasm/request-body/main.go` as an example.
* `proxy_on_http_response_headers`: run in the header_filter phase.
* `proxy_on_http_response_body`: run in the body_filter phase. To run this callback, we need to set property `wasm_process_resp_body` to non-empty value in `proxy_on_http_response_headers`. See `t/wasm/response-rewrite/main.go` as an example.

## Example

We have reimplemented some Lua plugin via Wasm, under `t/wasm/` of this repo:

* fault-injection
* forward-auth
* response-rewrite
