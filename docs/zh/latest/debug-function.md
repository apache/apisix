---
title: 调试功能
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

## `5xx` 响应状态码

500、502、503 等类似的 `5xx` 状态码，是由于服务器错误而响应的状态码，当一个请求出现 `5xx` 状态码时；它可能来源于 `APISIX` 或 `Upstream` 。如何识别这些响应状态码的来源，是一件很有意义的事，它能够快速的帮助我们确定问题的所在。(当修改 `conf/config.yaml` 的配置 `show_upstream_status_in_response_header` 为 `true` 时，会返回所有上游状态码，不仅仅是 `5xx` 状态。)

## 如何识别 `5xx` 响应状态码的来源

在请求的响应头中，通过 `X-APISIX-Upstream-Status` 这个响应头，我们可以有效的识别 `5xx` 状态码的来源。当 `5xx` 状态码来源于 `Upstream` 时，在响应头中可以看到 `X-APISIX-Upstream-Status` 这个响应头，并且这个响应头的值为响应的状态码。当 `5xx` 状态码来源于 `APISIX` 时，响应头中没有 `X-APISIX-Upstream-Status` 的响应头信息。也就是只有 `5xx` 状态码来源于 `Upstream` 时，才会有 `X-APISIX-Upstream-Status` 响应头。

## 示例

示例 1：`502` 响应状态码来源于 `Upstream` (IP 地址不可用)

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
$ curl http://127.0.0.1:9180/apisix/admin/routes/1  -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "methods": ["GET"],
    "upstream": {
        "nodes": {
            "127.0.0.1:1": 1
        },
        "type": "roundrobin"
    },
    "uri": "/hello"
}'
```

测试：

```shell
$ curl http://127.0.0.1:9080/hello -v
......
< HTTP/1.1 502 Bad Gateway
< Date: Wed, 25 Nov 2020 14:40:22 GMT
< Content-Type: text/html; charset=utf-8
< Content-Length: 154
< Connection: keep-alive
< Server: APISIX/2.0
< X-APISIX-Upstream-Status: 502
<
<html>
<head><title>502 Bad Gateway</title></head>
<body>
<center><h1>502 Bad Gateway</h1></center>
<hr><center>openresty</center>
</body>
</html>

```

具有 `X-APISIX-Upstream-Status: 502` 的响应头。

示例 2：`502` 响应状态码来源于 `APISIX`

```shell
$ curl http://127.0.0.1:9180/apisix/admin/routes/1  -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "plugins": {
        "fault-injection": {
            "abort": {
                "http_status": 500,
                "body": "Fault Injection!\n"
            }
        }
    },
    "uri": "/hello"
}'
```

测试：

```shell
$ curl http://127.0.0.1:9080/hello -v
......
< HTTP/1.1 500 Internal Server Error
< Date: Wed, 25 Nov 2020 14:50:20 GMT
< Content-Type: text/plain; charset=utf-8
< Transfer-Encoding: chunked
< Connection: keep-alive
< Server: APISIX/2.0
<
Fault Injection!
```

没有 `X-APISIX-Upstream-Status` 的响应头。

示例 3：`Upstream` 具有多节点，并且所有节点不可用

```shell
$ curl http://127.0.0.1:9180/apisix/admin/upstreams/1  -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "nodes": {
        "127.0.0.3:1": 1,
        "127.0.0.2:1": 1,
        "127.0.0.1:1": 1
    },
    "retries": 2,
    "type": "roundrobin"
}'
```

```shell
$ curl http://127.0.0.1:9180/apisix/admin/routes/1  -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/hello",
    "upstream_id": "1"
}'
```

测试：

```shell
$ curl http://127.0.0.1:9080/hello -v
< HTTP/1.1 502 Bad Gateway
< Date: Wed, 25 Nov 2020 15:07:34 GMT
< Content-Type: text/html; charset=utf-8
< Content-Length: 154
< Connection: keep-alive
< Server: APISIX/2.0
< X-APISIX-Upstream-Status: 502, 502, 502
<
<html>
<head><title>502 Bad Gateway</title></head>
<body>
<center><h1>502 Bad Gateway</h1></center>
<hr><center>openresty</center>
</body>
</html>
```

具有 `X-APISIX-Upstream-Status: 502, 502, 502` 的响应头。
