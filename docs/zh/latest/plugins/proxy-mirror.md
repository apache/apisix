---
title: proxy-mirror
keywords:
  - APISIX
  - API 网关
  - Proxy Mirror
description: proxy-mirror 插件将入口流量复制到 APISIX 并将其转发到指定的上游，而不会中断常规服务。
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
  <link rel="canonical" href="https://docs.api7.ai/hub/proxy-mirror" />
</head>

## 描述

`proxy-mirror` 插件将传入流量复制到 APISIX 并将其转发到指定的上游，而不会中断常规服务。您可以将插件配置为镜像所有流量或仅镜像一部分流量。该机制有利于一些用例，包括故障排除、安全检查、分析等。

请注意，APISIX 会忽略接收镜像流量的上游主机的任何响应。

## 参数

| 名称 | 类型   | 必选项 | 默认值 | 有效值 | 描述                                                                                                    |
| ---- | ------ | ------ | ------ | ------ | ------------------------------------------------------------------------------------------------------- |
| host | string | 是 | | | 将镜像流量转发到的主机的地址。该地址应包含方案但不包含路径，例如 `http://127.0.0.1:8081`。 |
| path | string | 否 | | | 将镜像流量转发到的主机的路径。如果未指定，则默认为路由的当前 URI 路径。如果插件正在镜像 gRPC 流量，则不适用。 |
| path_concat_mode | string | 否 | replace | ["replace", "prefix"] | 指定 `path` 时的连接模式。设置为 `replace` 时，配置的 `path` 将直接用作将镜像流量转发到的主机的路径。设置为 `prefix` 时，转发到的路径将是配置的 `path`，附加路由的请求 URI 路径。如果插件正在镜像 gRPC 流量，则不适用。 |
| sample_ratio | number | 否 | 1 | [0.00001, 1] | 将被镜像的请求的比例。默认情况下，所有流量都会被镜像。|

## 静态配置

默认情况下，插件的超时值在[默认配置](https://github.com/apache/apisix/blob/master/apisix/cli/config.lua)中预先配置。

要自定义这些值，请将相应的配置添加到 `config.yaml`。例如：

```yaml
plugin_attr:
  proxy-mirror:
    timeout:
      connect: 60s
      read: 60s
      send: 60s
```

重新加载 APISIX 以使更改生效。

## 示例

以下示例演示了如何为不同场景配置 `proxy-mirror`。

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### 镜像部分流量

以下示例演示了如何配置 `proxy-mirror` 以将 50% 的流量镜像到路由并将其转发到另一个上游服务。

启动一个示例 NGINX 服务器以接收镜像流量：

```shell
docker run -p 8081:80 --name nginx nginx
```

您应该在终端会话中看到 NGINX 访问日志和错误日志。

打开一个新的终端会话并使用 `proxy-mirror` 创建一个路由来镜像 50% 的流量：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "traffic-mirror-route",
    "uri": "/get",
    "plugins": {
      "proxy-mirror": {
        "host": "http://127.0.0.1:8081",
        "sample_ratio": 0.5
      }
    },
    "upstream": {
      "nodes": {
        "httpbin.org": 1
      },
      "type": "roundrobin"
    }
  }'
```

发送生成几个请求到路由：

```shell
curl -i "http://127.0.0.1:9080/get"
```

您应该会收到所有请求的 `HTTP/1.1 200 OK` 响应。

导航回 NGINX 终端会话，您应该会看到一些访问日志条目，大约是生成的请求数量的一半：

```text
172.17.0.1 - - [29/Jan/2024:23:11:01 +0000] "GET /get HTTP/1.1" 404 153 "-" "curl/7.64.1" "-"
```

这表明 APISIX 已将请求镜像到 NGINX 服务器。此处，HTTP 响应状态为 `404`，因为示例 NGINX 服务器未实现路由。

### 配置镜像超时

以下示例演示了如何更新插件的默认连接、读取和发送超时。当将流量镜像到非常慢的后端服务时，这可能很有用。

由于请求镜像是作为子请求实现的，子请求中的过度延迟可能导致原始请求被阻止。默认情况下，连接、读取和发送超时设置为 60 秒。要更新这些值，您可以在配置文件的 `plugin_attr` 部分中配置它们，如下所示：

```yaml title="conf/config.yaml"
plugin_attr:
  proxy-mirror:
    timeout:
      connect: 2000ms
      read: 2000ms
      send: 2000ms
```

重新加载 APISIX 以使更改生效。
