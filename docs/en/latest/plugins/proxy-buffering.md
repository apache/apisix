---
title: proxy-buffering
keywords:
  - Apache APISIX
  - API Gateway
  - Proxy Buffering
description: This document contains information about the Apache APISIX proxy-buffering Plugin, you can use it to disable nginx proxy buffering per route, which is essential for streaming responses such as Server-Sent Events (SSE).
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

The `proxy-buffering` Plugin controls the nginx proxy buffering behavior per route. When proxy buffering is disabled, nginx streams the upstream response directly to the client without accumulating it in memory or on disk first. This is essential for:

- **Server-Sent Events (SSE)**: Clients must receive events in real time, so buffering would delay or break the stream.
- **Streaming APIs**: Large or indefinite response bodies must flow continuously without waiting for the full body to be received.
- **Real-time data delivery**: Any use case requiring low-latency delivery of partial responses.

The plugin operates in the `rewrite` phase with a priority of **21991**, which means it runs before authentication plugins and can influence how the proxy location is selected in the APISIX pipeline.

## Attributes

| Name                      | Type    | Required | Default | Description                                                                                   |
| ------------------------- | ------- | -------- | ------- | --------------------------------------------------------------------------------------------- |
| disable_proxy_buffering   | boolean | False    | false   | When set to `true`, disables [`proxy_buffering`](https://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_buffering) for this route, enabling streaming responses. |

## Enable Plugin

The example below enables the Plugin on a specific Route to support streaming responses:

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl -i http://127.0.0.1:9180/apisix/admin/routes/1 \
  -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/sse",
    "plugins": {
        "proxy-buffering": {
            "disable_proxy_buffering": true
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

## Example usage

After enabling the plugin, send a request to the route:

```shell
curl -i http://127.0.0.1:9080/sse
```

Because `disable_proxy_buffering` is set to `true`, nginx will stream the response directly to the client. This is transparent to the caller but removes buffering latency introduced by nginx.

To verify the configuration was stored correctly:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
  -H "X-API-KEY: $admin_key"
```

The response will include the `proxy-buffering` plugin configuration in the route object.

## Delete Plugin

To remove the `proxy-buffering` Plugin, delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl -i http://127.0.0.1:9180/apisix/admin/routes/1 \
  -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/sse",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```
