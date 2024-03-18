---
title: HTTP3 协议
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

`APISIX` 支持 HTTP3 协议，目前仅支持在 `downstream` 和 `APISIX` 之间的连接中开启 HTTP/3。

## 使用示例

1. config.yaml 配置。

```yaml
apisix:
  ssl:
    listen:
      - port: 9443
        enable_http3: true   # enable HTTP/3
```

**注意** `enable_http3` 需要 `TLSv1.3`

1. 为 test.com 创建 SSL 对象。

```shell
curl http://127.0.0.1:9180/apisix/admin/ssls/1 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
     "cert" : "'"$(cat t/certs/apisix.crt)"'",
     "key": "'"$(cat t/certs/apisix.key)"'",
     "snis": ["test.com"]
}'
```

1. 创建 route

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -i -d '
{
    "uri": "/get",
    "hosts": ["test.com"],
    "methods": ["GET"],
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "localhost:80": 1
        }
    }
}'
```

3. 访问验证

使用 HTTP/3 访问 test.com：

- curl 版本 7.88.0+

```shell
curl -k -vvv -H "Host: test.com" -H "content-length: 0" --http3-only --resolve "test.com:9443:127.0.0.1" https://test.com:9443/get

* Added test.com:9443:127.0.0.1 to DNS cache
* Hostname test.com was found in DNS cache
*   Trying 127.0.0.1:9443...
* QUIC cipher selection: TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256:TLS_AES_128_CCM_SHA256
* Skipped certificate verification
* Connected to test.com (127.0.0.1) port 9443
* using HTTP/3
* [HTTP/3] [0] OPENED stream for https://test.com:9443/get
* [HTTP/3] [0] [:method: GET]
* [HTTP/3] [0] [:scheme: https]
* [HTTP/3] [0] [:authority: test.com]
* [HTTP/3] [0] [:path: /get]
* [HTTP/3] [0] [user-agent: curl/8.6.0]
* [HTTP/3] [0] [accept: */*]
* [HTTP/3] [0] [content-length: 0]
> GET /get HTTP/3
> Host: test.com
> User-Agent: curl/8.6.0
> Accept: */*
> content-length: 0
>
< HTTP/3 200
< content-type: text/plain; charset=utf-8
< content-length: 28
< date: Mon, 04 Mar 2024 04:38:42 GMT
< server: APISIX/3.8.0
<
* Connection #0 to host test.com left intact
```

## 已知问题

- 开启 HTTP/3 时，Tongsuo 相关测试用例会失败，因为 Tongsuo 不支持 QUIC TLS。
- 对于 HTTP/2 或 HTTP/3 请求，无论您使用哪种 HTTP 方法，请求都应发送 `Content-Length` 头部。
- APISIX-3.9 基于 NGINX-1.25.3，存在 HTTP/3 漏洞（CVE-2024-24989、CVE-2024-24990）。
