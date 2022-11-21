---
title: proxy-rewrite
keywords:
  - APISIX
  - Plugin
  - Proxy Rewrite
  - proxy-rewrite
description: 本文介绍了关于 Apache APISIX `proxy-rewrite` 插件的基本信息及使用方法。
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

`proxy-rewrite` 是处理上游代理信息重写的插件，支持对 `scheme`、`uri`、`host` 等信息进行重写。

## 属性

| 名称      | 类型          | 必选项 | 默认值 | 有效值             | 描述                                                                                                                                  |
| --------- | ------------- | ----- | ------- | ---------------------------------------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| uri       | string        | 否    |         |                                                                                                                                        | 转发到上游的新 `uri` 地址。支持 [NGINX variables](https://nginx.org/en/docs/http/ngx_http_core_module.html) 变量，例如：`$arg_name`。  |
| method    | string        | 否    |         | ["GET", "POST", "PUT", "HEAD", "DELETE", "OPTIONS","MKCOL", "COPY", "MOVE", "PROPFIND", "PROPFIND","LOCK", "UNLOCK", "PATCH", "TRACE"] | 将路由的请求方法代理为该请求方法。 |
| regex_uri | array[string] | 否    |         |                                                                                                                                        | 转发到上游的新 `uri` 地址。使用正则表达式匹配来自客户端的 `uri`，如果匹配成功，则使用模板替换转发到上游的 `uri`，如果没有匹配成功，则将客户端请求的 `uri` 转发至上游。当同时配置 `uri` 和 `regex_uri` 属性时，优先使用 `uri`。例如：["^/iresty/(.*)/(.*)/(.*)","/$1-$2-$3"] 第一个元素代表匹配来自客户端请求的 `uri` 正则表达式，第二个元素代表匹配成功后转发到上游的 `uri` 模板。但是目前 APISIX 仅支持一个 `regex_uri`，所以 `regex_uri` 数组的长度是 `2`。 |
| host      | string        | 否    |         |                   | 转发到上游的新 `host` 地址，例如：`iresty.com`。|
| headers   | object        | 否    |         |                   |   |
| headers.add     | object   | 否     |        |                 | 添加新的请求头，如果头已经存在，会追加到末尾。格式为 `{"name: value", ...}`。这个值能够以 `$var` 的格式包含 NGINX 变量，比如 `$remote_addr $balancer_ip`。                                                                                              |
| headers.set     | object  | 否     |        |                 | 改写请求头，如果请求头不存在，则会添加这个请求头。格式为 `{"name": "value", ...}`。这个值能够以 `$var` 的格式包含 NGINX 变量，比如 `$remote_addr $balancer_ip`。                                                                                                |
| headers.remove  | array   | 否     |        |                 | 移除响应头。格式为 `["name", ...]`。

## Header 优先级

Header 头的相关配置，遵循如下优先级进行执行：

`add` > `remove` > `set`

## 启用插件

你可以通过如下命令在指定路由上启用 `proxy-rewrite` 插件：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/test/index.html",
    "plugins": {
        "proxy-rewrite": {
            "uri": "/test/home.html",
            "host": "iresty.com",
            "headers": {
                "set": {
                    "X-Api-Version": "v1",
                    "X-Api-Engine": "apisix",
                    "X-Api-useless": ""
                },
                "add": {
                    "X-Request-ID": "112233"
                },
                "remove":[
                    "X-test"
                ]
            }
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:80": 1
        }
    }
}'
```

## 测试插件

通过上述命令启用插件后，可以使用如下命令测试插件是否启用成功：

```shell
curl -X GET http://127.0.0.1:9080/test/index.html
```

发送请求，查看上游服务的 `access.log`，如果输出信息与配置一致则表示 `proxy-rewrite` 插件已经生效。示例如下：

```
127.0.0.1 - [26/Sep/2019:10:52:20 +0800] iresty.com GET /test/home.html HTTP/1.1 200 38 - curl/7.29.0 - 0.000 199 107
```

## 禁用插件

当你需要禁用 `proxy-rewrite` 插件时，可以通过以下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/test/index.html",
    "plugins": {},
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:80": 1
        }
    }
}'
```
