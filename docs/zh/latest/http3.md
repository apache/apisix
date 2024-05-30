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

[HTTP/3](https://en.wikipedia.org/wiki/HTTP/3) 是 Hypertext Transfer Protocol(HTTP) 的第三个主要版本。与依赖 TCP 的前辈不同，HTTP/3 基于 [QUIC (Quick UDP Internet Connections) protocol](https://en.wikipedia.org/wiki/QUIC)。它带来了多项好处，减少了延迟并提高了性能：

* 实现不同网络连接之间的无缝过渡，例如从 Wi-Fi 切换到移动数据。
* 消除队头阻塞，以便丢失的数据包不会阻塞所有流。
* 在 TLS 握手的同时协商 TLS 版本，从而实现更快的连接。
* 默认提供加密，确保通过 HTTP/3 连接传输的所有数据都受到保护和保密。
* 在与客户端已建立连接的服务器通信时提供零往返时间 (0-RTT)。

APISIX 目前支持下游客户端和 APISIX 之间的 HTTP/3 连接。尚不支持与上游服务的 HTTP/3 连接。欢迎社区贡献。

:::caution

此功能尚未经过大规模测试，因此不建议用于生产使用。

:::

本文档将向您展示如何配置 APISIX 以在客户端和 APISIX 之间启用 HTTP/3 连接，并记录一些已知问题。

## 使用示例

### 启用 HTTP/3

将以下配置添加到 APISIX 的配置文件。该配置将在端口 `9443`（或其他端口）上启用 HTTP/3：

```yaml title="config.yaml"
apisix:
  ssl:
    listen:
      - port: 9443
        enable_http3: true
    ssl_protocols: TLSv1.3
```

:::info

如果您使用 Docker 部署 APISIX，请确保在 HTTP3 端口中允许 UDP，例如 `-p 9443:9443/udp`。

:::

然后重新加载 APISIX 以使配置更改生效：

```shell
apisix reload
```

### 生成证书和密钥

HTTP/3 需要 TLS。您可以利用购买的证书或自行生成证书。

如自行生成，首先生成证书颁发机构 (CA) 密钥和证书：

```shell
openssl genrsa -out ca.key 2048 && \
  openssl req -new -sha256 -key ca.key -out ca.csr -subj "/CN=ROOTCA" && \
  openssl x509 -req -days 36500 -sha256 -extensions v3_ca -signkey ca.key -in ca.csr -out ca.crt
```

接下来，生成具有 APISIX 通用名称的密钥和证书，并使用 CA 证书进行签名：

```shell
openssl genrsa -out server.key 2048 && \
  openssl req -new -sha256 -key server.key -out server.csr -subj "/CN=test.com" && \
  openssl x509 -req -days 36500 -sha256 -extensions v3_req \
  -CA ca.crt -CAkey ca.key -CAserial ca.srl -CAcreateserial \
  -in server.csr -out server.crt
```

### 配置 HTTPS

可选择性地将存储在 `server.crt` 和 `server.key` 中的内容加载到环境变量中：

```shell
server_cert=$(cat server.crt)
server_key=$(cat server.key)
```

创建一个保存服务器证书及其密钥的 SSL 对象：

```shell
curl -i "http://127.0.0.1:9180/apisix/admin/ssls" -X PUT -d '
{
  "id": "quickstart-tls-client-ssl",
  "sni": "test.com",
  "cert": "'"${server_cert}"'",
  "key": "'"${server_key}"'"
}'
```

### 创建路由

创建一个路由至 `httpbin.org`:

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

### 验证 HTTP/3 连接

验证前需要安装支持 HTTP/3 的 curl，如 [static-curl](https://github.com/stunnel/static-curl) 或其他支持 HTTP/3 的 curl。

发送一个请求到路由：

```shell
curl -kv --http3-only \
  -H "Host: test.com" \
  --resolve "test.com:9443:127.0.0.1" "https://test.com:9443/get"
```

应收到 `HTTP/3 200` 相应如下：

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

## 已知问题

- 对于 APISIX-3.9, Tongsuo 相关测试用例会失败，因为 Tongsuo 不支持 QUIC TLS。
- APISIX-3.9 基于 NGINX-1.25.3，存在 HTTP/3 漏洞（CVE-2024-24989、CVE-2024-24990）。
