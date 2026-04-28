---
title: mqtt-proxy
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - MQTT Proxy
description: The mqtt-proxy Plugin supports proxying and load balancing MQTT requests to MQTT servers, supporting MQTT versions 3.1.x and 5.0.
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
  <link rel="canonical" href="https://docs.api7.ai/hub/mqtt-proxy" />
</head>

## Description

The `mqtt-proxy` Plugin is an L4 Plugin that supports proxying and load balancing MQTT requests to MQTT servers. It supports MQTT versions [3.1.*](http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html) and [5.0](https://docs.oasis-open.org/mqtt/mqtt/v5.0/mqtt-v5.0.html). The Plugin must be configured on a stream Route, and APISIX should enable L4 traffic proxying.

## Attributes

| Name           | Type    | Required | Default | Description                                                                      |
|----------------|---------|----------|---------|----------------------------------------------------------------------------------|
| protocol_name  | string  | False    | "MQTT"  | Name of the protocol.                                                            |
| protocol_level | integer | True     |         | Level of the protocol. It should be `4` for MQTT `3.1.*` and `5` for MQTT `5.0`. |

## Examples

By default, APISIX only proxies L7 traffic. Before proceeding to examples, first ensure that you enable L4 traffic proxying in APISIX.

Update the configuration file as follows to enable L4 traffic proxying:

```yaml title="conf/config.yaml"
apisix:
  proxy_mode: http&stream   # Enable both L4 & L7 proxies
  stream_proxy:             # Configure L4 proxy
    tcp:
      - 9100                # Set TCP proxy listening port
```

Reload APISIX for changes to take effect. APISIX should now start listening for L4 traffic on port `9100`.

The examples below use a MQTT client from the Mosquitto project to publish and subscribe to messages. You can download it [here](https://mosquitto.org/download/) or use any other MQTT client of your choice.

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Proxy to a MQTT Broker

The following example demonstrates how you can configure a stream Route to proxy traffic to a hosted MQTT server and verify that APISIX can proxy MQTT messages successfully.

Create a stream Route to the MQTT server and configure the `mqtt-proxy` Plugin:

```shell
curl "http://127.0.0.1:9180/apisix/admin/stream_routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "mqtt-route",
    "plugins": {
      "mqtt-proxy": {
        "protocol_name": "MQTT",
        "protocol_level": 4
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "test.mosquitto.org:1883": 1
      }
    }
  }'
```

Open two terminal sessions. In the first one, subscribe to the test topic:

```shell
mosquitto_sub -h test.mosquitto.org -p 1883 -t "test/apisix"
```

In the other one, publish a sample message to the created Route:

```shell
mosquitto_pub -h 127.0.0.1 -p 9100 -t "test/apisix" -m "Hello APISIX"
```

You should see the message `Hello APISIX` in the first terminal.

### Load Balance MQTT Traffic

The following example demonstrates how you can configure a stream Route to load balance MQTT traffic to different MQTT servers.

When the Plugin is enabled, it registers a variable `mqtt_client_id` which can be used for load balancing. MQTT connections with different client IDs will be forwarded to different upstream nodes based on the consistent hash algorithm. If the client ID is missing, the client IP will be used instead.

Create a stream Route to two MQTT servers and configure the `mqtt-proxy` Plugin:

```shell
curl "http://127.0.0.1:9180/apisix/admin/stream_routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "mqtt-route",
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
          "host": "test.mosquitto.org",
          "port": 1883,
          "weight": 1
        },
        {
          "host": "broker.mqtt.cool",
          "port": 1883,
          "weight": 1
        }
      ]
    }
  }'
```

Open three terminal sessions. In the first one, subscribe to the test topic in the first MQTT broker:

```shell
mosquitto_sub -h test.mosquitto.org -p 1883 -t "test/apisix"
```

In the second terminal, subscribe to the same topic in the second MQTT broker:

```shell
mosquitto_sub -h broker.mqtt.cool -p 1883 -t "test/apisix"
```

In the third terminal, run the following commands a few times to send sample messages to the Route:

```shell
mosquitto_pub -h 127.0.0.1 -p 9100 -t "test/apisix" -m "Hello APISIX"
```

You should see the message `Hello APISIX` in both terminals, verifying the traffic was load balanced.

## Enabling mTLS with mqtt-proxy Plugin

Stream proxies use TCP connections and can accept TLS. Follow the guide about [how to accept TLS over TCP connections](../stream-proxy.md/#accept-tls-over-tcp-connection) to open a stream proxy with enabled TLS.

The `mqtt-proxy` Plugin is enabled through TCP communications on the specified port for the stream proxy, and will also require clients to authenticate via TLS if `tls` is set to `true`.

Configure `ssl` providing the CA certificate and the server certificate, together with a list of SNIs. Steps to protect `stream_routes` with `ssl` are equivalent to the ones to [protect Routes](../mtls.md/#protect-route).

### Create a stream_route using mqtt-proxy Plugin and mTLS

The following example creates a stream Route using the `mqtt-proxy` Plugin and configures it with the CA certificate, the client certificate and the client key (for self-signed certificates which are not trusted by your host, use the `-k` flag):

```shell
curl "http://127.0.0.1:9180/apisix/admin/stream_routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "mqtt-route",
    "plugins": {
      "mqtt-proxy": {
        "protocol_name": "MQTT",
        "protocol_level": 4
      }
    },
    "sni": "${your_sni_name}",
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "127.0.0.1:1980": 1
      }
    }
  }'
```

The `sni` name must match one or more of the SNIs provided to the SSL object that you created with the CA and server certificates.
