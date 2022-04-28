---
title: real-ip
keywords:
  - APISIX
  - Plugin
  - Real IP
  - real ip
description: 本文介绍了关于 Apache APISIX `real-ip` 插件的基本信息及使用方法。
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

`real-ip` 插件用于动态改变传递到 Apache APISIX 的客户端的 IP 地址和端口。

它的工作方式和 NGINX 中的 `ngx_http_realip_module` 模块一样，并且更加灵活。

:::info IMPORTANT

该插件要求 APISIX  运行在 [APISIX-OpenResty](../how-to-build.md#步骤-6-为-apache-apisix-构建-openresty) 上。

:::

## 属性

| 名称              | 类型          | 必选项 | 有效值                                                       | 描述                                                                                     |
|-------------------|---------------|-------|-------------------------------------------------------------|----------------------------------------------------------------------|
| source            | string        | 是    | 任何 NGINX 变量，如 `arg_realip` 或 `http_x_forwarded_for` 。 | 动态设置客户端的 IP 地址和端口。如果该值不包含端口，则不会更改客户端的端口。|
| trusted_addresses | array[string] | 否    | IP 或 CIDR 范围列表。                                         | 动态设置 `set_real_ip_from` 字段。                                    |

:::note

如果 `source` 属性中设置的地址丢失或者无效，该插件将不会更改客户端地址。

:::

## 启用插件

以下示例展示了如何在指定路由中启用 `real-ip` 插件：

```shell
curl -i http://127.0.0.1:9080/apisix/admin/routes/1  \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/index.html",
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
            "127.0.0.1:1980": 1
        }
    }
}'
```

## 测试插件

通过上述命令启用插件后，可以使用如下命令测试插件是否启用成功：

```shell
curl 'http://127.0.0.1:9080/index.html?realip=1.2.3.4:9080' -I
```

```shell
...
remote-addr: 1.2.3.4
remote-port: 9080
```

## 禁用插件

当你需要禁用 `real-ip` 插件时，可以通过以下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1  \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
