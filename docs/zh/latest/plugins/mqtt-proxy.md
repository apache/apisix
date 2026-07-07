---
title: mqtt-proxy
keywords:
  - APISIX
  - API 网关
  - Plugin
  - MQTT Proxy
description: mqtt-proxy 插件支持将 MQTT 请求代理和负载均衡到 MQTT 服务器，支持 MQTT 3.1.x 和 5.0 版本。
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

## 描述

`mqtt-proxy` 插件是一个 L4 插件，支持将 MQTT 请求代理和负载均衡到 MQTT 服务器。它支持 MQTT [3.1.*](http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html) 和 [5.0](https://docs.oasis-open.org/mqtt/mqtt/v5.0/mqtt-v5.0.html) 版本。该插件必须配置在流式路由上，且 APISIX 需要启用 L4 流量代理。

## 属性

| 名称           | 类型    | 必选项 | 默认值  | 描述                                                        |
|----------------|---------|--------|---------|-------------------------------------------------------------|
| protocol_name  | string  | 否     | "MQTT"  | 协议名称。                                                  |
| protocol_level | integer | 是     |         | 协议级别。MQTT `3.1.*` 应设为 `4`，MQTT `5.0` 应设为 `5`。  |

## 示例

默认情况下，APISIX 仅代理 L7 流量。在操作前，请先确保在 APISIX 中启用了 L4 流量代理。

按如下方式更新配置文件以启用 L4 流量代理：

```yaml title="conf/config.yaml"
apisix:
  proxy_mode: http&stream   # 同时启用 L4 和 L7 代理
  stream_proxy:             # 配置 L4 代理
    tcp:
      - 9100                # 设置 TCP 代理监听端口
```

重载 APISIX 使配置生效。APISIX 现在应开始在 `9100` 端口监听 L4 流量。

以下示例使用来自 Mosquitto 项目的 MQTT 客户端发布和订阅消息。你可以在[这里](https://mosquitto.org/download/)下载，或使用其他 MQTT 客户端。

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### 代理到 MQTT Broker

以下示例演示如何配置流式路由，将流量代理到托管的 MQTT 服务器，并验证 APISIX 能够成功代理 MQTT 消息。

创建流式路由并配置 `mqtt-proxy` 插件：

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

将配置同步到网关：

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

Gateway API 目前不支持配置 L4 插件。此示例暂时无法通过 Gateway API 完成。

:::

</TabItem>

<TabItem value="apisix-crd">

使用 APISIX CRD 将 `mqtt-proxy` 插件配置到流式路由：

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

应用配置：

```shell
kubectl apply -f mqtt-proxy-ic.yaml
```

</TabItem>

</Tabs>

</TabItem>

</Tabs>

打开两个终端会话。在第一个终端中，订阅测试主题：

```shell
mosquitto_sub -h test.mosquitto.org -p 1883 -t "test/apisix"
```

在另一个终端中，向创建的路由发布示例消息：

```shell
mosquitto_pub -h 127.0.0.1 -p 9100 -t "test/apisix" -m "Hello APISIX"
```

你应该在第一个终端中看到消息 `Hello APISIX`。

### 对 MQTT 流量进行负载均衡

以下示例演示如何配置流式路由，将 MQTT 流量负载均衡到不同的 MQTT 服务器。

启用该插件后，它会注册一个变量 `mqtt_client_id`，可用于负载均衡。不同客户端 ID 的 MQTT 连接将根据一致性哈希算法转发到不同的上游节点。如果客户端 ID 缺失，则使用客户端 IP 代替。

创建流式路由，并将 `mqtt-proxy` 插件配置为指向两个 MQTT 服务器：

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

将配置同步到网关：

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

Gateway API 目前不支持配置 L4 插件。此示例暂时无法通过 Gateway API 完成。

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

应用配置：

```shell
kubectl apply -f mqtt-proxy-ic.yaml
```

</TabItem>

</Tabs>

</TabItem>

</Tabs>

打开三个终端会话。在第一个终端中，订阅第一个 MQTT broker 的测试主题：

```shell
mosquitto_sub -h test.mosquitto.org -p 1883 -t "test/apisix"
```

在第二个终端中，订阅第二个 MQTT broker 的相同主题：

```shell
mosquitto_sub -h broker.mqtt.cool -p 1883 -t "test/apisix"
```

在第三个终端中，使用两个不同的客户端 ID 发送示例消息以验证负载均衡：

```shell
mosquitto_pub -h 127.0.0.1 -p 9100 -t "test/apisix" -m "Hello APISIX" -i "client-1"
mosquitto_pub -h 127.0.0.1 -p 9100 -t "test/apisix" -m "Hello APISIX" -i "client-2"
```

由于负载均衡基于 MQTT 客户端 ID 的一致性哈希，每个客户端 ID 会被一致地路由到同一个 broker。你应该看到每条消息出现在两个订阅终端之一，从而验证流量已分发到两个 broker。

## 使用 mqtt-proxy 插件启用 mTLS

流式代理使用 TCP 连接，可以支持 TLS。请参考[如何通过 TCP 连接接受 TLS](../stream-proxy.md/#accept-tls-over-tcp-connection)，打开启用了 TLS 的流式代理。

`mqtt-proxy` 插件通过流式代理指定端口上的 TCP 通信启用。如果 `tls` 设置为 `true`，还要求客户端通过 TLS 进行身份验证。

配置 `ssl` 以提供 CA 证书和服务器证书，以及 SNI 列表。使用 `ssl` 保护 `stream_routes` 的步骤等同于[保护路由](../mtls.md/#protect-route)。

### 创建使用 mqtt-proxy 插件和 mTLS 的 stream_route

以下示例创建了一个使用 `mqtt-proxy` 插件的 stream_route，并提供 CA 证书、客户端证书和客户端密钥（对于不受主机信任的自签名证书，请使用 `-k` 选项）：

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

`sni` 名称必须与使用 CA 和服务器证书创建的 SSL 对象的一个或多个 SNI 匹配。
