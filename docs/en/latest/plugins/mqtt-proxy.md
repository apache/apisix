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

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

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
curl "http://127.0.0.1:9180/apisix/admin/stream_routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "mqtt-route-proxy",
    "plugins": {
      "mqtt-proxy": {
        "protocol_name": "MQTT",
        "protocol_level": 4
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": [
        {
          "host": "test.mosquitto.org",
          "port": 1883,
          "weight": 1
        }
      ]
    }
  }'
```

</TabItem>

<TabItem value="adc">

```yaml title="adc.yaml"
services:
  - name: mqtt-service
    upstream:
      name: default
      scheme: tcp
      nodes:
        - host: test.mosquitto.org
          port: 1883
          weight: 1
    stream_routes:
      - name: mqtt-route
        server_port: 9100
        plugins:
          mqtt-proxy:
            protocol_name: MQTT
            protocol_level: 4
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

:::info

Attaching L4 plugins is currently not supported with Gateway API. At the moment, this example cannot be completed with Gateway API.

:::

</TabItem>

<TabItem value="apisix-crd">

Use APISIX CRD to attach the `mqtt-proxy` Plugin to the stream Route:

```yaml title="mqtt-proxy-ic.yaml"
apiVersion: v1
kind: Service
metadata:
  namespace: aic
  name: mqtt-broker
spec:
  type: ExternalName
  externalName: test.mosquitto.org
  ports:
    - name: mqtt
      port: 1883
      targetPort: 1883
---
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: mqtt-route
spec:
  ingressClassName: apisix
  stream:
    - name: mqtt-route
      protocol: TCP
      match:
        ingressPort: 9100
      backend:
        serviceName: mqtt-broker
        servicePort: 1883
      plugins:
        - name: mqtt-proxy
          enable: true
          config:
            protocol_name: MQTT
            protocol_level: 4
```

Apply the configuration:

```shell
kubectl apply -f mqtt-proxy-ic.yaml
```

</TabItem>

</Tabs>

</TabItem>

</Tabs>

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
curl "http://127.0.0.1:9180/apisix/admin/stream_routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "mqtt-route-lb",
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

</TabItem>

<TabItem value="adc">

```yaml title="adc.yaml"
services:
  - name: mqtt-service
    upstream:
      name: default
      scheme: tcp
      type: chash
      key: mqtt_client_id
      nodes:
        - host: test.mosquitto.org
          port: 1883
          weight: 1
        - host: broker.mqtt.cool
          port: 1883
          weight: 1
    stream_routes:
      - name: mqtt-route
        server_port: 9100
        plugins:
          mqtt-proxy:
            protocol_name: MQTT
            protocol_level: 4
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

:::info

Attaching L4 plugins is currently not supported with Gateway API. At the moment, this example cannot be completed with Gateway API.

:::

</TabItem>

<TabItem value="apisix-crd">

```yaml title="mqtt-proxy-ic.yaml"
apiVersion: v1
kind: Service
metadata:
  namespace: aic
  name: mqtt-brokers
spec:
  ports:
    - name: mqtt
      port: 1883
      protocol: TCP
---
apiVersion: discovery.k8s.io/v1
kind: EndpointSlice
metadata:
  namespace: aic
  name: mqtt-brokers-1
  labels:
    kubernetes.io/service-name: mqtt-brokers
addressType: FQDN
ports:
  - name: mqtt
    protocol: TCP
    port: 1883
endpoints:
  - addresses:
      - test.mosquitto.org
  - addresses:
      - broker.mqtt.cool
---
apiVersion: apisix.apache.org/v2
kind: ApisixUpstream
metadata:
  namespace: aic
  name: mqtt-brokers
spec:
  ingressClassName: apisix
  loadbalancer:
    type: chash
    key: mqtt_client_id
    hashOn: vars
---
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: mqtt-route
spec:
  ingressClassName: apisix
  stream:
    - name: mqtt-route
      protocol: TCP
      match:
        ingressPort: 9100
      backend:
        serviceName: mqtt-brokers
        servicePort: 1883
      plugins:
        - name: mqtt-proxy
          enable: true
          config:
            protocol_name: MQTT
            protocol_level: 4
```

Apply the configuration:

```shell
kubectl apply -f mqtt-proxy-ic.yaml
```

</TabItem>

</Tabs>

</TabItem>

</Tabs>

Open three terminal sessions. In the first one, subscribe to the test topic in the first MQTT broker:

```shell
mosquitto_sub -h test.mosquitto.org -p 1883 -t "test/apisix"
```

In the second terminal, subscribe to the same topic in the second MQTT broker:

```shell
mosquitto_sub -h broker.mqtt.cool -p 1883 -t "test/apisix"
```

In the third terminal, send sample messages with two different client IDs to verify load balancing:

```shell
mosquitto_pub -h 127.0.0.1 -p 9100 -t "test/apisix" -m "Hello APISIX" -i "client-1"
mosquitto_pub -h 127.0.0.1 -p 9100 -t "test/apisix" -m "Hello APISIX" -i "client-2"
```

Because load balancing is based on a consistent hash of the MQTT client ID, each client ID is consistently routed to one broker. You should see each message appear in one of the two subscriber terminals, verifying that traffic is distributed across both brokers.

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
    "id": "mqtt-route-mtls",
    "plugins": {
      "mqtt-proxy": {
        "protocol_name": "MQTT",
        "protocol_level": 4
      }
    },
    "sni": "${your_sni_name}",
    "upstream": {
      "type": "roundrobin",
      "nodes": [
        {
          "host": "127.0.0.1",
          "port": 1980,
          "weight": 1
        }
      ]
    }
  }'
```

The `sni` name must match one or more of the SNIs provided to the SSL object that you created with the CA and server certificates.
