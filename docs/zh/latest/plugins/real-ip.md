---
title: real-ip
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

`real-ip` 插件用于动态改变传递到 `APISIX` 的客户端的 `IP` 和端口。

它工作方式和 `Nginx` 里 `ngx_http_realip_module` 模块一样，并且更为灵活。

**该插件要求 `APISIX` 运行在 [APISIX-OpenResty](../how-to-build.md#步骤6：为-apache-apisix-构建-openresty) 上。**

## 属性

| 名称      | 类型          | 必选项 | 默认值    | 有效值                                                                    | 描述                                                                                                                                         |
| --------- | ------------- | ----------- | ---------- | ------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| source      | string        | 必填    |            | 任何 Nginx 变量，如 `arg_realip` 或 `http_x_forwarded_for` | 根据变量的值 `APISIX` 动态设置客户端的 `IP` 和端口。如果该值不包含端口，则不会更改客户端的端口。 |
| trusted_addresses| array[string] | 可选    |            | `IP` 或 `CIDR` 范围列表 | 动态设置 `set_real_ip_from` 指令 |

如果 `source` 设置的远程地址缺失或无效，该插件则直接放行，不会更改客户端地址。

## 如何启用

下面是一个示例，在指定的 `route` 上开启了 `real-ip` 插件：

```shell
curl -i http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

使用 `curl` 访问：

```shell
curl 'http://127.0.0.1:9080/index.html?realip=1.2.3.4:9080' -I
...
remote-addr: 1.2.3.4
remote-port: 9080
```

## 禁用插件

想要禁用该插件时很简单，在路由 `plugins` 配置块中删除对应 `JSON` 配置，不需要重启服务，即可立即生效禁用该插件。

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
