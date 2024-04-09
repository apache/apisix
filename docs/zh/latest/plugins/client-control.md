---
title: client-control
keywords:
  - APISIX
  - API 网关
  - Client Control
description: 本文介绍了 Apache APISIX proxy-control 插件的相关操作，你可以使用此插件动态地控制 NGINX 处理客户端的请求的行为。
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

`client-control` 插件能够通过设置客户端请求体大小的上限来动态地控制 NGINX 处理客户端的请求。

:::info 重要

此插件需要 APISIX 在 [APISIX-Runtime](../FAQ.md#如何构建-apisix-Runtime-环境) 环境上运行。更多信息请参考 [apisix-build-tools](https://github.com/api7/apisix-build-tools)。

:::

## 属性

| 名称      | 类型          | 必选项 | 有效值                                                                    | 描述                                                                                                                                                                                    |
| --------- | ------------- | ----------- | ------------------------------------------------------------------------ |---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| max_body_size | integer        | 否    | [0,...] | 设置客户端请求体的最大上限，动态调整 [`client_max_body_size`](https://nginx.org/en/docs/http/ngx_http_core_module.html#client_max_body_size) 的大小，单位为字节。当设置 `max_body_size` 为 0 时，将不会对客户端请求体大小进行检查。 |

## 启用插件

以下示例展示了如何在指定路由上启用 `client-control` 插件，并设置 `max_body_size`：

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
        "client-control": {
            "max_body_size" : 1
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

## 测试插件

启用插件后，使用 `curl` 命令请求该路由：

```shell
curl -i http://127.0.0.1:9080/index.html -d '123'
```

因为在配置插件时设置了 `max_body_size` 为 `1`，所以返回的 HTTP 响应头中如果带有 `413` 状态码，则表示插件生效：

```shell
HTTP/1.1 413 Request Entity Too Large
...
<html>
<head><title>413 Request Entity Too Large</title></head>
<body>
<center><h1>413 Request Entity Too Large</h1></center>
<hr><center>openresty</center>
</body>
</html>
```

## 删除插件

当你需要删除该插件时，可以通过以下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  \
  -H "X-API-KEY: $admin_key" -X PUT -d '
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
