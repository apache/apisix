---
title: skywalking
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - SkyWalking
description: skywalking 插件支持与 Apache SkyWalking 集成以进行请求跟踪。
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
  <link rel="canonical" href="https://docs.api7.ai/hub/skywalking" />
</head>

## 描述

`skywalking` 插件支持与 [Apache SkyWalking](https://skywalking.apache.org) 集成以进行请求跟踪。

SkyWalking 使用其原生的 Nginx Lua 跟踪器从服务和 URI 角度提供跟踪、拓扑分析和指标。APISIX 支持 HTTP 协议与 SkyWalking 服务器交互。

服务端目前支持 HTTP 和 gRPC 两种协议，在 APISIX 中目前只支持 HTTP 协议。

## 静态配置

默认情况下，插件的服务名称和端点地址已在[默认配置](https://github.com/apache/apisix/blob/master/apisix/cli/config.lua)中预先配置。

要自定义这些值，请将相应的配置添加到 `config.yaml`。例如：

```yaml
plugin_attr:
  skywalking:
    report_interval: 3      # 上报间隔时间（秒）。
    service_name: APISIX    # SkyWalking 记者的服务名称。
    service_instance_name: "APISIX Instance Name"   # SkyWalking 记者的服务实例名称。
                                                    # 设置为 $hostname 可获取本地主机名。
    endpoint_addr: http://127.0.0.1:12800           # SkyWalking HTTP 端点。
```

重新加载 APISIX 以使更改生效。

## 属性

| 名称         | 类型    | 必选项 | 默认值  | 有效值       | 描述                                                  |
| ------------ | ------ | ------ | ------ | ------------ | ----------------------------------------------------- |
| sample_ratio | number | 是     | 1      | [0.00001, 1] | 请求采样频率。将采样率设置为 `1` 表示对所有请求进行采样。 |

## 示例

要遵循示例，请按照 [Skywalking 的文档](https://skywalking.apache.org/docs/main/next/en/setup/backend/backend-docker/) 使用 Docker Compose 启动存储、OAP 和 Booster UI。设置完成后，OAP 服务器应监听 `12800`，您应该能够通过 [http://localhost:8080](http://localhost:8080) 访问 UI。

更新 APISIX 配置文件以启用 `skywalking` 插件（默认情况下处于禁用状态），并更新端点地址：

```yaml title="config.yaml"
plugins:
  - skywalking
  - ...

plugin_attr:
  skywalking:
    report_interval: 3
    service_name: APISIX
    service_instance_name: APISIX Instance
    endpoint_addr: http://192.168.2.103:12800
```

重新加载 APISIX 以使配置更改生效。

:::

以下示例展示了如何通过 Admin API 配置插件元数据：

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### 跟踪所有请求

以下示例演示了如何跟踪通过路由的所有请求。

使用 `skywalking` 创建路由，并将采样率配置为 1 以跟踪所有请求：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "skywalking-route",
    "uri": "/anything",
    "plugins": {
      "skywalking": {
        "sample_ratio": 1
      }
    },
    "upstream": {
      "nodes": {
        "httpbin.org:80": 1
      },
      "type": "roundrobin"
    }
  }'
```

向路由发送几个请求：

```shell
curl -i "http://127.0.0.1:9080/anything"
```

您应该收到 `HTTP/1.1 200 OK` 响应。

在 [Skywalking UI](http://localhost:8080) 中，导航到 __General Service__ > __Services__。您应该看到一个名为 `APISIX` 的服务，其中包含与您的请求相对应的跟踪：

![SkyWalking APISIX 跟踪](https://static.apiseven.com/uploads/2025/01/15/UdwiO8NJ_skywalking-traces.png)

### 将跟踪与日志关联

以下示例演示了如何在路由上配置 `skywalking-logger` 插件，以记录到达路由的请求信息。

使用 `skywalking-logger` 插件创建路由，并使用你的 OAP 服务器 URI 配置该插件：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "skywalking-logger-route",
    "uri": "/anything",
    "plugins": {
      "skywalking": {
        "sample_ratio": 1
      },
      "skywalking-logger": {
        "endpoint_addr": "http://192.168.2.103:12800"
      }
    },
    "upstream": {
      "nodes": {
        "httpbin.org:80": 1
      },
      "type": "roundrobin"
    }
  }'
```

生成几个对路由的请求：

```shell
curl -i "http://127.0.0.1:9080/anything"
```

您应该会收到 `HTTP/1.1 200 OK` 响应。

在 [Skywalking UI](http://localhost:8080) 中，导航到 __General Service__ > __Services__。您应该会看到一个名为 `APISIX` 的服务，其中包含与您的请求相对应的跟踪，您可以在其中查看相关日志：

![trace context](https://static.apiseven.com/uploads/2025/01/16/soUpXm6b_trace-view-logs.png)

![associated log](https://static.apiseven.com/uploads/2025/01/16/XD934LvU_associated-logs.png)
