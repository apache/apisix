---
title: proxy-control
keywords:
  - APISIX
  - API 网关
  - Proxy Control
description: 本文介绍了 Apache APISIX proxy-control 插件的相关操作，你可以使用此插件动态地控制 NGINX 代理的行为。
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

使用 `proxy-control` 插件能够动态地控制 NGINX 代理的相关行为。

:::info 重要

此插件需要 APISIX 在 [APISIX-Runtime](../FAQ.md#如何构建-apisix-runtime-环境) 环境上运行。更多信息请参考 [apisix-build-tools](https://github.com/api7/apisix-build-tools)。

:::

## 属性

| 名称      | 类型          | 必选项 | 默认值    | 有效值                                                                    | 描述                                                                                                                                         |
| --------- | ------------- | ----------- | ---------- | ------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| request_buffering | boolean        | 否    |  true            |  | 如果设置为 `true`，插件将动态设置 [`proxy_request_buffering`](http://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_request_buffering)。 |

## 启用插件

以下示例展示了如何在指定路由上启用 `proxy-control` 插件：

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
    "uri": "/upload",
    "plugins": {
        "proxy-control": {
            "request_buffering": false
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

启用插件后，使用 `curl` 命令请求该路由进行一个大文件的上传测试：

```shell
curl -i http://127.0.0.1:9080/upload -d @very_big_file
```

如果在错误日志中没有找到关于 "a client request body is buffered to a temporary file" 的信息，则说明插件生效。

## 删除插件

当你需要删除该插件时，可以通过以下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
  -H "X-API-KEY: $admin_key" -X PUT -d
{
    "uri": "/upload",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```
