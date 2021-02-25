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

## `5xx` response status code

Similar `5xx` status codes such as 500, 502, 503, etc., are the status codes in response to a server error. When a request has a `5xx` status code; it may come from `APISIX` or `Upstream`. How to identify the source of these response status codes is a very meaningful thing. It can quickly help us determine the problem.

## How to identify the source of the `5xx` response status code

In the response header of the request, through the response header of `X-APISIX-Upstream-Status`, we can effectively identify the source of the `5xx` status code. When the `5xx` status code comes from `Upstream`, the response header `X-APISIX-Upstream-Status` can be seen in the response header, and the value of this response header is the response status code. When the `5xx` status code is derived from `APISIX`, there is no response header information of `X-APISIX-Upstream-Status` in the response header. That is, only when the status code of `5xx` is derived from Upstream will the `X-APISIX-Upstream-Status` response header appear.

## Example

>Example 1: `502` response status code comes from `Upstream` (IP address is not available)

```shell
$ curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

Test:

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

It has a response header of `X-APISIX-Upstream-Status: 502`.

>Example 2: `502` response status code comes from `APISIX`

```shell
$ curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

Test：

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

There is no response header for `X-APISIX-Upstream-Status`.

>Example 3: `Upstream` has multiple nodes, and all nodes are unavailable

```shell
$ curl http://127.0.0.1:9080/apisix/admin/upstreams/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
$ curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/hello",
    "upstream_id": "1"
}'
```

Test：

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

It has a response header of `X-APISIX-Upstream-Status: 502, 502, 502`.
