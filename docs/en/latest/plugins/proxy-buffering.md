---
title: proxy-buffering
keywords:
  - Apache APISIX
  - API Gateway
  - Proxy Buffering
description: The proxy-buffering Plugin disables nginx proxy buffering per route to enable streaming responses such as Server-Sent Events (SSE).
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
  <link rel="canonical" href="https://docs.api7.ai/hub/proxy-buffering" />
</head>

## Description

The `proxy-buffering` Plugin disables nginx proxy buffering for the configured route. When proxy buffering is disabled, nginx streams the upstream response directly to the client without accumulating it in memory or on disk first.

This is particularly useful for:

- **Server-Sent Events (SSE)**: Clients must receive events in real time; buffering would delay or break the stream.
- **Streaming APIs**: Large or indefinite response bodies must flow continuously without waiting for the full body.
- **Real-time data delivery**: Any use case requiring low-latency delivery of partial responses.

## Attributes

| Name                      | Type    | Required | Default | Description                                                                                   |
| ------------------------- | ------- | -------- | ------- | --------------------------------------------------------------------------------------------- |
| disable_proxy_buffering   | boolean | No       | false   | When set to `true`, disables [`proxy_buffering`](https://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_buffering) for this route, enabling streaming responses. |

## Examples

The examples below demonstrate how you can configure the `proxy-buffering` Plugin for different scenarios.

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Disable Proxy Buffering for Streaming Responses

The following example disables proxy buffering for a route that serves Server-Sent Events (SSE):

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

Send a request to the route:

```shell
curl -i -N -H "Accept: text/event-stream" http://127.0.0.1:9080/sse
```

Because `disable_proxy_buffering` is `true`, nginx streams each SSE event from the upstream to the client as it arrives, without buffering.

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
