---
title: sr-enable-disable
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - Stream Route
  - sr-enable-disable
description: The sr-enable-disable Plugin acts as a runtime enable/disable switch for stream routes, allowing you to control whether a stream route accepts or rejects incoming TCP/TLS connections.
---
<!--
Licensed to the Apache Software Foundation (ASF) under one or more
contributor license agreements.  See the NOTICE file distributed with
this work for additional information regarding copyright ownership.
The ASF licenses this file to You under the Apache License, Version 2.0
(the "License"); you may not use this file except in compliance with
the License.  You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
-->
## Description

The `sr-enable-disable` Plugin acts as a runtime enable/disable switch for any stream route it is attached to. When `enabled` is set to `true`, connections are allowed through to the upstream as usual. When set to `false`, all inbound connections are rejected and the client receives a configurable message before the socket is closed.

This is useful for maintenance windows, gradual rollouts, or operational scenarios where you need to temporarily take a stream route offline without removing it from the configuration.

>[!NOTE]
>This Plugin operates at the stream (L4) level and does not have access to HTTP-specific features such as status codes or headers. It works with raw TCP/TLS connections.

## Attributes

| Name        | Type    | Required | Default                            | Description                                                                 |
|-------------|---------|----------|------------------------------------|-----------------------------------------------------------------------------|
| enabled     | boolean | True     | -                                  | When `true`, connections are allowed. When `false`, all connections are rejected. |
| decline_msg | string  | False    | "Stream route in disabled state."  | Message sent to the client before the connection is closed.                 |

## Enable Plugin

To use this Plugin, you need to first enable the stream proxy in your configuration file (`conf/config.yaml`). The below configuration enables both HTTP and stream proxies and listens on the `9100` TCP port:

```yaml title="conf/config.yaml"
apisix:
    proxy_mode: http&stream
    stream_proxy:
      tcp:
        - 9100
```

After updating the configuration, reload APISIX for the changes to take effect.

## Examples

The examples below demonstrate how you can configure the `sr-enable-disable` Plugin for different scenarios.

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

### Enable a Stream Route

The following example demonstrates how to create a stream route with the Plugin enabled, allowing connections to pass through to the upstream.

Create a stream route with the `sr-enable-disable` Plugin:

```shell
curl "http://127.0.0.1:9180/apisix/admin/stream_routes/1" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "plugins": {
      "sr-enable-disable": {
        "enabled": true
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "127.0.0.1:1995": 1
      }
    }
  }'
```

Send a TCP connection to the stream route:

```shell
echo "hello" | nc 127.0.0.1 9100
```

The connection should be forwarded to the upstream and you should receive a response from the upstream service.

### Disable a Stream Route

The following example demonstrates how to disable a stream route so that all incoming connections are rejected with a custom message.

Create a stream route with the `sr-enable-disable` Plugin disabled:

```shell
curl "http://127.0.0.1:9180/apisix/admin/stream_routes/1" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "plugins": {
      "sr-enable-disable": {
        "enabled": false,
        "decline_msg": "This route is under maintenance."
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "127.0.0.1:1995": 1
      }
    }
  }'
```

Send a TCP connection to the stream route:

```shell
echo "hello" | nc 127.0.0.1 9100
```

You should receive the following message before the connection is closed:

```text
This route is under maintenance.
```

### Toggle a Route at Runtime

To re-enable a previously disabled stream route, update the Plugin configuration by setting `enabled` to `true`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/stream_routes/1" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "plugins": {
      "sr-enable-disable": {
        "enabled": true,
        "decline_msg": "This route is under maintenance."
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "127.0.0.1:1995": 1
      }
    }
  }'
```

Connections will now be forwarded to the upstream again.
