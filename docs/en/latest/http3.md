---
title: HTTP/3 Protocol
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

[HTTP/3](https://en.wikipedia.org/wiki/HTTP/3) is the third major version of the Hypertext Transfer Protocol (HTTP). Unlike its predecessors which rely on TCP, HTTP/3 is based on [QUIC (Quick UDP Internet Connections) protocol](https://en.wikipedia.org/wiki/QUIC). It brings several benefits that collectively result in reduced latency and improved performance:

* enabling seamless transition between different network connections, such as switching from Wi-Fi to mobile data.
* eliminating head-of-line blocking, so that a lost packet does not block all streams.
* negotiating TLS versions at the same time as the TLS handshakes, allowing for faster connections.
* providing encryption by default, ensuring that all data transmitted over an HTTP/3 connection is protected and confidential.
* providing zero round-trip time (0-RTT) when communicating with servers that clients already established connections to.

APISIX currently supports HTTP/3 connections between downstream clients and APISIX. HTTP/3 connections with upstream services are not yet supported, and contributions are welcomed.

:::caution

This feature is currently experimental and not recommended for production use.

:::

This document will show you how to configure APISIX to enable HTTP/3 connections between client and APISIX and document a few known issues.

## Usage

### Enable HTTP/3 in APISIX

Enable HTTP/3 on port `9443` (or a different port) by adding the following configurations to APISIX's `config.yaml` configuration file:

```yaml title="config.yaml"
apisix:
  ssl:
    listen:
      - port: 9443
        enable_http3: true
    ssl_protocols: TLSv1.3
```

:::info

If you are deploying APISIX using Docker, make sure to allow UDP in the HTTP3 port, such as `-p 9443:9443/udp`.

:::

Then reload APISIX for configuration changes to take effect:

```shell
apisix reload
```

### Generate Certificates and Keys

HTTP/3 requires TLS. You can leverage the purchased certificates or self-generate them, whichever applicable.

To self-generate, first generate the certificate authority (CA) key and certificate:

```shell
openssl genrsa -out ca.key 2048 && \
  openssl req -new -sha256 -key ca.key -out ca.csr -subj "/CN=ROOTCA" && \
  openssl x509 -req -days 36500 -sha256 -extensions v3_ca -signkey ca.key -in ca.csr -out ca.crt
```

Next, generate the key and certificate with a common name for APISIX, and sign with the CA certificate:

```shell
openssl genrsa -out server.key 2048 && \
  openssl req -new -sha256 -key server.key -out server.csr -subj "/CN=test.com" && \
  openssl x509 -req -days 36500 -sha256 -extensions v3_req \
  -CA ca.crt -CAkey ca.key -CAserial ca.srl -CAcreateserial \
  -in server.csr -out server.crt
```

### Configure HTTPS

Optionally load the content stored in `server.crt` and `server.key` into shell variables:

```shell
server_cert=$(cat server.crt)
server_key=$(cat server.key)
```

Create an SSL certificate object to save the server certificate and its key:

```shell
curl -i "http://127.0.0.1:9180/apisix/admin/ssls" -X PUT -d '
{
  "id": "quickstart-tls-client-ssl",
  "sni": "test.com",
  "cert": "'"${server_cert}"'",
  "key": "'"${server_key}"'"
}'
```

### Create a Route

Create a sample route to `httpbin.org`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT -d '
{
  "id":"httpbin-route",
  "uri":"/get",
  "upstream": {
    "type":"roundrobin",
    "nodes": {
      "httpbin.org:80": 1
    }
  }
}'
```

### Verify HTTP/3 Connections

Install [static-curl](https://github.com/stunnel/static-curl) or any other curl executable that has HTTP/3 support.

Send a request to the route:

```shell
curl -kv --http3-only \
  -H "Host: test.com" \
  --resolve "test.com:9443:127.0.0.1" "https://test.com:9443/get"
```

You should receive an `HTTP/3 200` response similar to the following:

```text
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
* [HTTP/3] [0] [user-agent: curl/8.7.1]
* [HTTP/3] [0] [accept: */*]
> GET /get HTTP/3
> Host: test.com
> User-Agent: curl/8.7.1
> Accept: */*
>
* Request completely sent off
< HTTP/3 200
...
{
  "args": {},
  "headers": {
    "Accept": "*/*",
    "Content-Length": "0",
    "Host": "test.com",
    "User-Agent": "curl/8.7.1",
    "X-Amzn-Trace-Id": "Root=1-6656013a-27da6b6a34d98e3e79baaf5b",
    "X-Forwarded-Host": "test.com"
  },
  "origin": "172.19.0.1, 123.40.79.456",
  "url": "http://test.com/get"
}
* Connection #0 to host test.com left intact
```

## Known Issues

- For APISIX-3.9, test cases of Tongsuo will fail because the Tongsuo does not support QUIC TLS.
- APISIX-3.9 is based on NGINX-1.25.3 with  vulnerabilities in HTTP/3 (CVE-2024-24989, CVE-2024-24990).
