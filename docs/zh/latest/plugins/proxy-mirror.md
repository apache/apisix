---
title: proxy-mirror
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

代理镜像插件，该插件提供了镜像客户端请求的能力。

注：镜像请求返回的响应会被忽略。

### 参数

| 名称 | 类型   | 必选项 | 默认值 | 有效值 | 描述                                                                                                    |
| ---- | ------ | ------ | ------ | ------ | ------------------------------------------------------------------------------------------------------- |
| host | string | 必须   |        |        | 指定镜像服务地址，例如：http://127.0.0.1:9797（地址中需要包含 schema ：http或https，不能包含 path 部分） |
| path | string | 可选   |        |        | 指定镜像请求的路径。如不指定，当前路径将被使用。 |
| sample_ratio | number | 可选    | 1       |  [0.00001, 1]     | 镜像请求采样率 |

### 示例

#### 启用插件

示例1：为特定路由启用 `proxy-mirror` 插件：

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

测试：

```shell
$ curl http://127.0.0.1:9080/hello -i
HTTP/1.1 200 OK
Content-Type: application/octet-stream
Content-Length: 12
Connection: keep-alive
Server: APISIX web server
Date: Wed, 18 Mar 2020 13:01:11 GMT
Last-Modified: Thu, 20 Feb 2020 14:21:41 GMT

hello world
```

> 由于指定的 mirror 地址是 127.0.0.1:9797，所以验证此插件是否已经正常工作需要在端口为 9797 的服务上确认，例如，我们可以通过 python 启动一个简单的 server： python -m SimpleHTTPServer 9797。

#### 禁用插件

移除插件配置中相应的 JSON 配置可立即禁用该插件，无需重启服务：

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

这时该插件已被禁用。

## 指定mirror子请求的超时时间

我们可以在 `conf/config.yaml` 的 `plugin_attr` 中指定子请求的超时时间。这在连接复用的场景下 mirror 流量到一个非常慢的后端服务时非常有用。

| 名称 | 类型 | 默认值 | 描述 |
| --- | --- | --- | --- |
| connect | string | 60s | 镜像请求到上游的连接超时时间 |
| read | string | 60s | 镜像请求到上游的读超时时间 |
| send | string | 60s | 镜像请求到上游的写超时时间 |

```yaml
plugin_attr:
  proxy-mirror:
    timeout:
      connect: 2000ms
      read: 2000ms
      send: 2000ms
```
