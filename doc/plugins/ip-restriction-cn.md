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

[English](ip-restriction.md)

# 目录
- [**名字**](#名字)
- [**属性**](#属性)
- [**如何启用**](#如何启用)
- [**测试插件**](#测试插件)
- [**禁用插件**](#禁用插件)

## 名字

`ip-restriction` 可以通过以下方式限制对服务或路线的访问，将 IP 地址列入白名单或黑名单。 单个 IP 地址，多个 IP地址 或 CIDR 范围，可以使用类似 10.10.10.0/24 的 CIDR 表示法(将很快支持 IPv6)。

## 属性

* `whitelist`: 可选，加入白名单的IP地址 或 CIDR 范围
* `blacklist`: 可选，加入黑名单的IP地址 或 CIDR 范围

只能单独启用白名单或黑名单，两个不能一起使用。

## 如何启用

下面是一个示例，在指定的 route 上开启了 `ip-restriction` 插件:

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -X PUT -d '
{
    "uri": "/index.html",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    },
    "plugins": {
        "ip-restriction": {
            "whitelist": [
                "127.0.0.1",
                "113.74.26.106/24"
            ]
        }
    }
}'
```

## 测试插件

访问 `127.0.0.1`:

```shell
$ curl http://127.0.0.1:9080/index.html
HTTP/1.1 200 OK
...
```

访问 `127.0.0.2`:

```shell
$ curl http://127.0.0.2:9080/index.html -i
HTTP/1.1 403 Forbidden
...
{"message":"Your IP address is not allowed"}
```

## 禁用插件

当你想去掉 `ip-restriction` 插件的时候，很简单，在插件的配置中把对应的 json 配置删除即可，无须重启服务，即刻生效：

```shell
$ curl http://127.0.0.1:2379/v2/keys/apisix/routes/1 -X PUT -d value='
{
    "uri": "/index.html",
    "plugins": {},
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "39.97.63.215:80": 1
        }
    }
}'
```

现在就已移除 `ip-restriction` 插件，其它插件的开启和移除也类似。

