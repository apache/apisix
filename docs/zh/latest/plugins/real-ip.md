---
title: real-ip
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - Real IP
description: real-ip 插件允许 Apache APISIX 通过 HTTP 请求头或 HTTP 查询字符串中传递的 IP 地址设置客户端的真实 IP。
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
  <link rel="canonical" href="https://docs.api7.ai/hub/real-ip" />
</head>

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

## 描述

`real-ip` 插件使用请求头或查询参数中的 IP 地址替换客户端地址。当可信代理传递已验证的客户端地址，而 APISIX 会将该代理识别为客户端时，可以使用此插件。

该插件在功能上类似于 NGINX 的 [ngx_http_realip_module](https://nginx.org/en/docs/http/ngx_http_realip_module.html)，但提供了更多的灵活性。

## 属性

| 名称              | 类型          | 是否必需 | 默认值 | 有效值                     | 描述                                                                 |
|-------------------|---------------|----------|--------|----------------------------|----------------------------------------------------------------------|
| source            | string        | 是       |        |                            | 内置的 [APISIX 变量](https://apisix.apache.org/zh/docs/apisix/apisix-variable/)或 [NGINX 变量](https://nginx.org/en/docs/varindex.html)，例如 `http_x_forwarded_for` 或 `arg_realip`。变量值应为表示真实客户端的有效 IP 地址，可以包含端口。 |
| trusted_addresses | array[string] | 否       |        | IPv4 或 IPv6 地址数组（支持 CIDR 表示法） | 可以通过 `source` 提供替代地址的可信代理地址。如果配置了此属性，只有当前的 `remote_addr` 与列表匹配时，插件才会更改客户端地址。如果省略此属性，插件会接受任意对端在 `source` 中提供的值。当不可信客户端可以控制源值时，应配置可信地址。 |
| recursive         | boolean       | 否       | false  |                            | 当 `source` 为 `http_x_forwarded_for` 且配置了 `trusted_addresses` 时，控制插件如何选择地址。设为 `false` 时，插件选择请求头中的最后一个地址。设为 `true` 时，插件从右向左扫描请求头，跳过可信的中间代理地址，并选择最后一个非可信地址。如果所有地址都可信，则选择最左侧地址。对于其他 `source` 或未配置 `trusted_addresses` 的情况，此属性不生效。 |

:::note
如果 `source` 属性中设置的地址丢失或者无效，该插件将不会更改客户端地址。
:::

## 信任转发的客户端信息

APISIX 可以在多个阶段获取客户端地址。每项信任配置检查的地址及其作用均不同。

| 阶段 | 检查的地址 | 作用 |
| --- | --- | --- |
| NGINX 静态真实 IP 配置 | 根据 `nginx_config.http.real_ip_from` 检查连接地址。APISIX 默认信任 `127.0.0.1` 和 `unix:`。 | 对于可信来源，`real_ip_header` 读取配置的请求头（默认为 `X-Real-IP`），替换 `remote_addr`，并将连接地址保存在 `realip_remote_addr` 中。 |
| 全局 `apisix.trusted_addresses` | `realip_remote_addr` | 保留来自所配置可信地址的 `Forwarded` 和 `X-Forwarded-*` 信息。如果已配置的列表不信任连接地址，APISIX 会在插件和上游收到这些请求头之前进行清理。 |
| 插件的 `trusted_addresses` | 当前的 `remote_addr`，它可能已经被 NGINX 重写 | 如果地址可信，插件会使用 `source` 中的地址进行替换。 |

未配置全局信任列表时，为了保持兼容性，APISIX 会保留传入的 `X-Forwarded-For` 地址链，并追加连接地址。APISIX 仍会使用自身观测到的值替换转发的协议、主机和端口，并清除 `Forwarded`。如果已配置的信任列表不包含连接地址，APISIX 还会丢弃传入的 `X-Forwarded-For` 地址链。

只信任由你管理的代理，并配置这些代理使用已验证的客户端地址覆盖源请求头。当插件跳过请求时，`remote_addr` 会保留 NGINX 传入的值。

## 示例

以下示例分别从查询参数、可信代理请求头或多级代理链中设置客户端地址。

:::note

你可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### 从 URI 参数获取真实客户端地址

以下示例演示了如何使用 URI 参数更新客户端 IP 地址。

创建如下路由：

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
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "real-ip-route",
    "uri": "/get",
    "plugins": {
      "real-ip": {
        "source": "arg_realip",
        "trusted_addresses": ["127.0.0.0/24"]
      },
      "response-rewrite": {
        "headers": {
          "remote_addr": "$remote_addr",
          "remote_port": "$remote_port"
        }
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```

</TabItem>

<TabItem value="adc">

```yaml title="adc.yaml"
services:
  - name: httpbin
    routes:
      - name: real-ip-route
        uris:
          - /get
        plugins:
          real-ip:
            source: arg_realip
            trusted_addresses:
              - 127.0.0.0/24
          response-rewrite:
            headers:
              remote_addr: $remote_addr
              remote_port: $remote_port
    upstream:
      type: roundrobin
      nodes:
        - host: httpbin.org
          port: 80
          weight: 1
```

同步配置到网关：

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

```yaml title="real-ip-ic.yaml"
apiVersion: v1
kind: Service
metadata:
  namespace: aic
  name: httpbin-external-domain
spec:
  type: ExternalName
  externalName: httpbin.org
---
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  namespace: aic
  name: real-ip-plugin-config
spec:
  plugins:
    - name: real-ip
      config:
        source: arg_realip
        trusted_addresses:
          - 127.0.0.0/24
    - name: response-rewrite
      config:
        headers:
          remote_addr: $remote_addr
          remote_port: $remote_port
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: real-ip-route
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: Exact
            value: /get
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: real-ip-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

</TabItem>

<TabItem value="apisix-crd">

```yaml title="real-ip-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixUpstream
metadata:
  namespace: aic
  name: httpbin-external-domain
spec:
  ingressClassName: apisix
  externalNodes:
  - type: Domain
    name: httpbin.org
---
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: real-ip-route
spec:
  ingressClassName: apisix
  http:
    - name: real-ip-route
      match:
        paths:
          - /get
      upstreams:
        - name: httpbin-external-domain
      plugins:
        - name: real-ip
          config:
            source: arg_realip
            trusted_addresses:
              - 127.0.0.0/24
        - name: response-rewrite
          config:
            headers:
              remote_addr: $remote_addr
              remote_port: $remote_port
```

</TabItem>

</Tabs>

应用配置：

```shell
kubectl apply -f real-ip-ic.yaml
```

</TabItem>

</Tabs>

向路由发送带有 URL 参数中的真实 IP 和端口的请求：

```shell
curl -i "http://127.0.0.1:9080/get?realip=1.2.3.4:9080"
```

你应看到响应包含以下头：

```text
remote_addr: 1.2.3.4
remote_port: 9080
```

### 从请求头获取真实客户端地址

本示例从 `X-Verified-Client-IP` 读取已验证的客户端地址，并展示请求头缺失或直连对端不可信时的行为。

创建如下路由：

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
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "real-ip-route",
    "uri": "/get",
    "plugins": {
      "real-ip": {
        "source": "http_x_verified_client_ip",
        "trusted_addresses": ["127.0.0.0/24"]
      },
      "response-rewrite": {
        "headers": {
          "remote_addr": "$remote_addr"
        }
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```

</TabItem>

<TabItem value="adc">

```yaml title="adc.yaml"
services:
  - name: httpbin
    routes:
      - name: real-ip-route
        uris:
          - /get
        plugins:
          real-ip:
            source: http_x_verified_client_ip
            trusted_addresses:
              - 127.0.0.0/24
          response-rewrite:
            headers:
              remote_addr: $remote_addr
    upstream:
      type: roundrobin
      nodes:
        - host: httpbin.org
          port: 80
          weight: 1
```

同步配置到网关：

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

```yaml title="real-ip-ic.yaml"
apiVersion: v1
kind: Service
metadata:
  namespace: aic
  name: httpbin-external-domain
spec:
  type: ExternalName
  externalName: httpbin.org
---
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  namespace: aic
  name: real-ip-plugin-config
spec:
  plugins:
    - name: real-ip
      config:
        source: http_x_verified_client_ip
        trusted_addresses:
          - 127.0.0.0/24
    - name: response-rewrite
      config:
        headers:
          remote_addr: $remote_addr
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: real-ip-route
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: Exact
            value: /get
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: real-ip-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

</TabItem>

<TabItem value="apisix-crd">

```yaml title="real-ip-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixUpstream
metadata:
  namespace: aic
  name: httpbin-external-domain
spec:
  ingressClassName: apisix
  externalNodes:
  - type: Domain
    name: httpbin.org
---
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: real-ip-route
spec:
  ingressClassName: apisix
  http:
    - name: real-ip-route
      match:
        paths:
          - /get
      upstreams:
        - name: httpbin-external-domain
      plugins:
        - name: real-ip
          config:
            source: http_x_verified_client_ip
            trusted_addresses:
              - 127.0.0.0/24
        - name: response-rewrite
          config:
            headers:
              remote_addr: $remote_addr
```

</TabItem>

</Tabs>

应用配置：

```shell
kubectl apply -f real-ip-ic.yaml
```

</TabItem>

</Tabs>

发送一个请求，模拟可信的本地代理提供已验证的客户端地址：

```shell
curl -i "http://127.0.0.1:9080/get" \
  -H "X-Verified-Client-IP: 198.51.100.20"
```

你应看到响应包含以下头：

```text
remote_addr: 198.51.100.20
```

不提供 `X-Verified-Client-IP`，再次发送请求：

```shell
curl -i "http://127.0.0.1:9080/get"
```

APISIX 会记录 `missing real address` 日志，并保留原有客户端地址。对于本地直连请求，响应包含 `remote_addr: 127.0.0.1`。

如需验证信任边界，请将 `trusted_addresses` 改为 `["192.0.2.10/32"]`，使用同一配置方式重新应用配置，然后再次发送第一个请求。直连对端不再匹配可信地址列表，因此 APISIX 会忽略提供的请求头，响应中将显示网关观测到的对端地址。测试后请恢复可信地址。

### 在多个代理之后获取真实客户端地址

本示例从多个可信代理添加的 [`X-Forwarded-For`](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/X-Forwarded-For) 地址链中解析原始客户端地址。

创建如下路由：

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
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
  "id": "real-ip-route",
  "uri": "/get",
  "plugins": {
    "real-ip": {
      "source": "http_x_forwarded_for",
      "recursive": true,
      "trusted_addresses": ["192.128.0.0/16", "127.0.0.1/32"]
    },
    "response-rewrite": {
      "headers": {
        "remote_addr": "$remote_addr"
      }
    }
  },
  "upstream": {
    "type": "roundrobin",
    "nodes": {
      "httpbin.org:80": 1
    }
  }
}'
```

</TabItem>

<TabItem value="adc">

```yaml title="adc.yaml"
services:
  - name: httpbin
    routes:
      - name: real-ip-route
        uris:
          - /get
        plugins:
          real-ip:
            source: http_x_forwarded_for
            recursive: true
            trusted_addresses:
              - 192.128.0.0/16
              - 127.0.0.1/32
          response-rewrite:
            headers:
              remote_addr: $remote_addr
    upstream:
      type: roundrobin
      nodes:
        - host: httpbin.org
          port: 80
          weight: 1
```

同步配置到网关：

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

```yaml title="real-ip-ic.yaml"
apiVersion: v1
kind: Service
metadata:
  namespace: aic
  name: httpbin-external-domain
spec:
  type: ExternalName
  externalName: httpbin.org
---
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  namespace: aic
  name: real-ip-plugin-config
spec:
  plugins:
    - name: real-ip
      config:
        source: http_x_forwarded_for
        recursive: true
        trusted_addresses:
          - 192.128.0.0/16
          - 127.0.0.1/32
    - name: response-rewrite
      config:
        headers:
          remote_addr: $remote_addr
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: real-ip-route
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: Exact
            value: /get
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: real-ip-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

</TabItem>

<TabItem value="apisix-crd">

```yaml title="real-ip-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixUpstream
metadata:
  namespace: aic
  name: httpbin-external-domain
spec:
  ingressClassName: apisix
  externalNodes:
  - type: Domain
    name: httpbin.org
---
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: real-ip-route
spec:
  ingressClassName: apisix
  http:
    - name: real-ip-route
      match:
        paths:
          - /get
      upstreams:
        - name: httpbin-external-domain
      plugins:
        - name: real-ip
          config:
            source: http_x_forwarded_for
            recursive: true
            trusted_addresses:
              - 192.128.0.0/16
              - 127.0.0.1/32
        - name: response-rewrite
          config:
            headers:
              remote_addr: $remote_addr
```

</TabItem>

</Tabs>

应用配置：

```shell
kubectl apply -f real-ip-ic.yaml
```

</TabItem>

</Tabs>

向路由发送请求：

```shell
curl -i "http://127.0.0.1:9080/get" \
  -H "X-Forwarded-For: 127.0.0.2, 192.128.1.1, 127.0.0.1"
```

你应看到响应包含以下头：

```text
remote_addr: 127.0.0.2
```
