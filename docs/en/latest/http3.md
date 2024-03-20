---
title: HTTP3 protocol
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

`APISIX` supports HTTP3 protocol. Currently, it only supports opening HTTP/3 connection between downstream and APISIX.

## Usage example

1. config.yaml configuration.

```yaml
apisix:
  ssl:
    listen:
      - port: 9443
        enable_http3: true   # enable HTTP/3
```

**note** `enable_http3` requires `TLSv1.3`

1. Create an SSL object for test.com.

```shell
curl http://127.0.0.1:9180/apisix/admin/ssls/1 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
     "cert" : "'"$(cat t/certs/apisix.crt)"'",
     "key": "'"$(cat t/certs/apisix.key)"'",
     "snis": ["test.com"]
}'
```

1. Create route

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

3. Access verification

Access test.com using HTTP/3:

- curl version 7.88.0+

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

## Known Issues

- When HTTP/3 is turned on, test cases of Tongsuo will fail because the Tongsuo does not support QUIC TLS.
- For HTTP/2 or HTTP/3 the request should send `content-length` header no matter what HTTP methods you use.
- APISIX-3.9 is based on NGINX-1.25.3 with  vulnerabilities in HTTP/3 (CVE-2024-24989, CVE-2024-24990).
