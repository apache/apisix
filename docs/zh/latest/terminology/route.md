---
title: Route
keywords:
  - API 网关
  - Apache APISIX
  - Route
  - 路由
description: 本文讲述了路由的概念以及使用方法。
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

Route（也称为路由）是 APISIX 中最基础和最核心的资源对象，APISIX 可以通过路由定义规则来匹配客户端请求，根据匹配结果加载并执行相应的插件，最后将请求转发给到指定的上游服务。

## 配置简介

路由中主要包含三部分内容：

- 匹配规则：比如 `uri`、`host`、`remote_addr` 等等，你也可以自定义匹配规则，详细信息请参考 [Route body 请求参数](../admin-api.md#route-request-body-parameters)。
- 插件配置：你可以根据业务需求，在路由中配置相应的插件来实现功能。详细信息请参考 [Plugin](./plugin.md) 和 [plugin-config](./plugin-config.md)。
- 上游信息：路由会根据配置的负载均衡信息，将请求按照规则转发至相应的上游。详细信息请参考 [Upstream](./upstream.md)。

下图示例是一些 Route 规则的实例，当某些属性值相同时，图中用相同颜色标识。

![路由示例](../../../assets/images/routes-example.png)

你可以在路由中完成所有参数的配置，该方式设置容易设置，每个路由的相对独立自由度比较高。示例如下：

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl -i http://127.0.0.1:9180/apisix/admin/routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/index.html",
    "plugins": {
        "limit-count": {
            "count": 2,
            "time_window": 60,
            "rejected_code": 503,
            "key_type": "var",
            "key": "remote_addr"
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

当你的路由中有比较多的重复配置（比如启用相同的插件配置或上游信息），你也可以通过配置 [Service](service.md) 和 [Upstream](upstream.md) 的 ID 或者其他对象的 ID 来完成路由配置。示例如下：

```shell
curl -i http://127.0.0.1:9180/apisix/admin/routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
  "uri": "/index.html",
  "plugin_config_id": "123456789apacheapisix",
  "upstream_id": "1"
}'
```

:::tip 提示

APISIX 所有的资源对象的 ID，均使用字符串格式，如果使用的上游 ID、服务 ID 或其他资源对象的 ID 大于 14 个字符时，请务必使用字符串形式表示该资源对象。例如：

```json
  "plugin_config_id": "1234a67891234apisix",
  "service_id": "434199918991639234",
  "upstream_id": "123456789123456789"
```

:::

## 配置示例

以下示例创建的路由，是把 URI 为 `/index.html` 的请求代理到地址为 `127.0.0.1:1980` 的上游服务。

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -i -d '
{
    "uri": "/index.html",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```

```shell
HTTP/1.1 201 Created
Date: Sat, 31 Aug 2019 01:17:15 GMT
Content-Type: text/plain
Transfer-Encoding: chunked
Connection: keep-alive
Server: APISIX web server

{"node":{"value":{"uri":"\/index.html","upstream":{"nodes":{"127.0.0.1:1980":1},"type":"roundrobin"}},"createdIndex":61925,"key":"\/apisix\/routes\/1","modifiedIndex":61925}}
```

当接收到成功应答后，表示该路由已成功创建。

更多信息，请参考 [Admin API 的 Route 对象](../admin-api.md#route)。
