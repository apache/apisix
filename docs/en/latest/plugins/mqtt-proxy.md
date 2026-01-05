---
title: mqtt-proxy
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - MQTT Proxy
description: This document contains information about the Apache APISIX mqtt-proxy Plugin. The `mqtt-proxy` Plugin is used for dynamic load balancing with `client_id` of MQTT.
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

The `mqtt-proxy` Plugin is used for dynamic load balancing with `client_id` of MQTT. It only works in stream model.

This Plugin supports both the protocols [3.1.*](http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html) and [5.0](https://docs.oasis-open.org/mqtt/mqtt/v5.0/mqtt-v5.0.html).

## Attributes

| Name           | Type    | Required   | Description                                                                       |
|----------------|---------|------------|-----------------------------------------------------------------------------------|
| protocol_name  | string  | False      | Name of the protocol. Defaults to `MQTT`.                                         |
| protocol_level | integer | True       | Level of the protocol. It should be `4` for MQTT `3.1.*` and `5` for MQTT `5.0`.  |

## Enable Plugin

To enable the Plugin, you need to first enable the `stream_proxy` configuration in your configuration file (`conf/config.yaml`). The below configuration represents listening on the `9100` TCP port:

```yaml title="conf/config.yaml"
    ...
    router:
        http: 'radixtree_uri'
        ssl: 'radixtree_sni'
    proxy_mode: http&stream
    stream_proxy:                 # TCP/UDP proxy
      tcp:                        # TCP proxy port list
        - 9100
    dns_resolver:
    ...
```

You can now send the MQTT request to port `9100`.

You can now create a stream Route and enable the `mqtt-proxy` Plugin:

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/stream_routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "plugins": {
        "mqtt-proxy": {
            "protocol_name": "MQTT",
            "protocol_level": 4
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": [{
            "host": "127.0.0.1",
            "port": 1980,
            "weight": 1
        }]
    }
}'
```

:::note

If you are using Docker in macOS, then `host.docker.internal` is the right parameter for the `host` attribute.

:::

This Plugin exposes a variable `mqtt_client_id` which can be used for load balancing as shown below:

```shell
curl http://127.0.0.1:9180/apisix/admin/stream_routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "plugins": {
        "mqtt-proxy": {
            "protocol_name": "MQTT",
            "protocol_level": 4
        }
    },
    "upstream": {
        "type": "chash",
        "key": "mqtt_client_id",
        "nodes": [
        {
            "host": "127.0.0.1",
            "port": 1995,
            "weight": 1
        },
        {
            "host": "127.0.0.2",
            "port": 1995,
            "weight": 1
        }
        ]
    }
}'
```

MQTT connections with different client ID will be forwarded to different nodes based on the consistent hash algorithm. If client ID is missing, client IP is used instead for load balancing.

## Enabling mTLS with mqtt-proxy plugin

Stream proxies use TCP connections and can accept TLS. Follow the guide about [how to accept tls over tcp connections](../stream-proxy.md/#accept-tls-over-tcp-connection) to open a stream proxy with enabled TLS.

The `mqtt-proxy` plugin is enabled through TCP communications on the specified port for the stream proxy, and will also require clients to authenticate via TLS if `tls` is set to `true`.

Configure `ssl` providing the CA certificate and the server certificate, together with a list of SNIs. Steps to protect `stream_routes` with `ssl` are equivalent to the ones to [protect Routes](../mtls.md/#protect-route).

### Create a stream_route using mqtt-proxy plugin and mTLS

Here is an example of how create a stream_route which is using the `mqtt-proxy` plugin, providing the CA certificate, the client certificate and the client key (for self-signed certificates which are not trusted by your host, use the `-k` flag):

```shell
curl 127.0.0.1:9180/apisix/admin/stream_routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "plugins": {
        "mqtt-proxy": {
            "protocol_name": "MQTT",
            "protocol_level": 4
        }
    },
    "sni": "${your_sni_name}",
    "upstream": {
        "nodes": {
            "127.0.0.1:1980": 1
        },
        "type": "roundrobin"
    }
}'
```

The `sni` name must match one or more of the SNIs provided to the SSL object that you created with the CA and server certificates.

## Delete Plugin

To remove the `mqtt-proxy` Plugin you can remove the corresponding configuration as shown below:

```shell
curl http://127.0.0.1:9180/apisix/admin/stream_routes/1 -H "X-API-KEY: $admin_key" -X DELETE
```
