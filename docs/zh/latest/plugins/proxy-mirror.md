---
title: proxy-mirror
keywords:
  - APISIX
  - API 网关
  - Proxy Mirror
description: 本文介绍了 Apache APISIX proxy-mirror 插件的相关操作，你可以使用此插件镜像客户端的请求。
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

## 描述

`proxy-mirror` 插件提供了镜像客户端请求的能力。流量镜像是将线上真实流量拷贝到镜像服务中，以便在不影响线上服务的情况下，对线上流量或请求内容进行具体的分析。

:::note 注意

镜像请求返回的响应会被忽略。

:::

## 参数

| 名称 | 类型   | 必选项 | 默认值 | 有效值 | 描述                                                                                                    |
| ---- | ------ | ------ | ------ | ------ | ------------------------------------------------------------------------------------------------------- |
| host | string | 是   |        |        | 指定镜像服务的地址，地址中需要包含 `schema`（`http(s)` 或 `grpc(s)`），但不能包含 `path` 部分。例如 `http://127.0.0.1:9797`。 |
| path | string | 否   |        |        | 指定镜像请求的路径。如果不指定，则默认会使用当前路径。如果是为了镜像 grpc 流量，这个选项不再适用。|
| path_concat_mode | string | 否   |   replace     | ["replace", "prefix"]       | 当指定镜像请求的路径时，设置请求路径的拼接模式。`replace` 模式将会直接使用 `path` 作为镜像请求的路径。`prefix` 模式将会使用 `path` + `来源请求 URI` 作为镜像请求的路径。当然如果是为了镜像 grpc 流量，这个选项也不再适用。|
| sample_ratio | number | 否    | 1       |  [0.00001, 1]     | 镜像请求的采样率。当设置为 `1` 时为全采样。 |

## 启用插件

以下示例展示了如何在指定路由上启用 `proxy-mirror` 插件：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  \
  -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "plugins": {
        "proxy-mirror": {
           "host": "http://127.0.0.1:9797"
        }
    },
    "upstream": {
        "nodes": {
            "127.0.0.1:1999": 1
        },
        "type": "roundrobin"
    },
    "uri": "/hello"
}'
```

### 指定镜像子请求的超时时间

我们可以在 `conf/config.yaml` 文件内的 `plugin_attr` 中指定子请求的超时时间。由于镜像请求是以子请求的方式实现，子请求的延迟将会导致原始请求阻塞，直到子请求完成，才可以恢复正常。因此可以配置超时时间，来避免子请求出现过大的延迟而影响原始请求。

| 名称 | 类型 | 默认值 | 描述 |
| --- | --- | --- | --- |
| connect | string | 60s | 镜像请求到上游的连接超时时间。 |
| read | string | 60s | APISIX 与镜像服务器维持连接的时间；如果在该时间内，APISIX 没有收到镜像服务器的响应，则关闭连接。 |
| send | string | 60s | APISIX 与镜像服务器维持连接的时间；如果在该时间内，APISIX 没有发送请求，则关闭连接。 |

```yaml
plugin_attr:
  proxy-mirror:
    timeout:
      connect: 2000ms
      read: 2000ms
      send: 2000ms
```

## 测试插件

:::tip 提示

因为指定的镜像地址是 `127.0.0.1:9797`，所以验证此插件是否正常工作需要在端口为 `9797` 的服务上确认。

我们可以通过 `python` 启动一个简单的服务：

```shell
python -m http.server 9797
```

:::

按上述配置启用插件后，使用 `curl` 命令请求该路由，请求将被镜像到所配置的主机上：

```shell
curl http://127.0.0.1:9080/hello -i
```

返回的 HTTP 响应头中如果带有 `200` 状态码，则表示插件生效：

```shell
HTTP/1.1 200 OK
...
hello world
```

## 删除插件

当你需要删除该插件时，可以通过以下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  \
  -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/hello",
    "plugins": {},
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1999": 1
        }
    }
}'
```
