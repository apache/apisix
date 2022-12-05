---
title: 配置客户端与 APISIX 之间的双向认证（mTLS）
keywords:
  - mTLS
  - API 网关
  - APISIX
description: 本文介绍了如何在客户端和 Apache APISIX 之间配置双向认证（mTLS）。
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

mTLS 是一种双向身份认证的方式。如果在你的网络环境中，要求只有受信任的客户端才可以访问服务端，那么可以启用 mTLS 来验证客户端的身份，保证服务端 API 的安全。本文主要介绍了如何配置客户端与 Apache APISIX 之间的双向认证（mTLS）。

## 配置

本示例包含以下过程：

1. 生成证书；
2. 在 APISIX 中配置证书；
3. 在 APISIX 中创建并配置路由；
4. 测试验证。

为了使测试结果更加清晰，本文提到的示例会向上游传递一些有关客户端证书的信息，其中包括：`serial`，`fingerprint` 和 `common name`。

### 生成证书

我们需要生成三个测试证书，分别是根证书、服务器证书、客户端证书。只需通过以下命令，就可以通过 `OpenSSL` 生成我们需要的测试证书。

```shell
# 根证书
openssl genrsa -out ca.key 2048
openssl req -new -sha256 -key ca.key -out ca.csr -subj "/CN=ROOTCA"
openssl x509 -req -days 36500 -sha256 -extensions v3_ca -signkey ca.key -in ca.csr -out ca.cer

# 服务器证书
openssl genrsa -out server.key 2048
# 注意：CN 值中的 `test.com` 为我们要测试的域名/主机名。
openssl req -new -sha256 -key server.key -out server.csr -subj "/CN=test.com"
openssl x509 -req -days 36500 -sha256 -extensions v3_req  -CA  ca.cer -CAkey ca.key  -CAserial ca.srl  -CAcreateserial -in server.csr -out server.cer

# 客户端证书
openssl genrsa -out client.key 2048
openssl req -new -sha256 -key client.key  -out client.csr -subj "/CN=CLIENT"
openssl x509 -req -days 36500 -sha256 -extensions v3_req  -CA  ca.cer -CAkey ca.key  -CAserial ca.srl  -CAcreateserial -in client.csr -out client.cer

# 将客户端证书转换为 pkcs12 供 Windows 使用（可选）
openssl pkcs12 -export -clcerts -in client.cer -inkey client.key -out client.p12
```

### 在 APISIX 中配置证书

使用 `curl` 命令请求 APISIX Admin API 创建一个 SSL 资源并指定 SNI。

:::note 注意

证书中的换行需要替换为其转义字符 `\n`

:::

```shell
curl -X PUT 'http://127.0.0.1:9180/apisix/admin/ssls/1' \
--header 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' \
--header 'Content-Type: application/json' \
--data-raw '{
    "sni": "test.com",
    "cert": "<服务器证书公钥>",
    "key": "<服务器证书私钥>",
    "client": {
        "ca": "<客户端证书公钥>"
    }
}'
```

- `sni`：指定证书的域名（CN），当客户端尝试通过 TLS 与 APISIX 握手时，APISIX 会将 `ClientHello` 中的 SNI 数据与该字段进行匹配，找到对应的服务器证书进行握手。
- `cert`：服务器证书的公钥。
- `key`：服务器证书的私钥。
- `client.ca`：客户端证书的公钥。为了演示方便，这里使用了同一个 `CA`。

### 配置测试路由

使用 `curl` 命令请求 APISIX Admin API 创建一个路由。

```shell
curl -X PUT 'http://127.0.0.1:9180/apisix/admin/routes/1' \
--header 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' \
--header 'Content-Type: application/json' \
--data-raw '{
    "uri": "/anything",
    "plugins": {
        "proxy-rewrite": {
            "headers": {
                "X-Ssl-Client-Fingerprint": "$ssl_client_fingerprint",
                "X-Ssl-Client-Serial": "$ssl_client_serial",
                "X-Ssl-Client-S-DN": "$ssl_client_s_dn"
            }
        }
    },
    "upstream": {
        "nodes": {
            "httpbin.org":1
        },
        "type":"roundrobin"
    }
}'
```

APISIX 会根据 SNI 和上一步创建的 SSL 资源自动处理 TLS 握手，所以我们不需要在路由中指定主机名（但也可以显式地指定主机名）。

另外，上面 `curl` 命令中，我们启用了 `proxy-rewrite` 插件，它将动态地更新请求头的信息，示例中变量值的来源是 `NGINX` 变量，你可以在这里找到它们：http://nginx.org/en/docs/http/ngx_http_ssl_module.html#variables。

### 测试验证

由于我们使用域名 `test.com` 作为测试域名，在开始验证之前，我们必须先将测试域名添加到你的 DNS 或者本地的 `hosts` 文件中。

1. 如果我们不使用 `hosts`，只是想测试一下结果，那么你可以使用下面的命令直接进行测试：

```
curl --resolve "test.com:9443:127.0.0.1" https://test.com:9443/anything -k --cert ./client.cer --key ./client.key
```

2. 如果你需要修改 `hosts`，请阅读下面示例（以 Ubuntu 为例）：

- 修改 /etc/hosts 文件

  ```shell
  # 127.0.0.1 localhost
  127.0.0.1 test.com
  ```

- 验证测试域名是否生效

  ```shell
  ping test.com

  PING test.com (127.0.0.1) 56(84) bytes of data.
  64 bytes from localhost.localdomain (127.0.0.1): icmp_seq=1 ttl=64 time=0.028 ms
  64 bytes from localhost.localdomain (127.0.0.1): icmp_seq=2 ttl=64 time=0.037 ms
  64 bytes from localhost.localdomain (127.0.0.1): icmp_seq=3 ttl=64 time=0.036 ms
  64 bytes from localhost.localdomain (127.0.0.1): icmp_seq=4 ttl=64 time=0.031 ms
  ^C
  --- test.com ping statistics ---
  4 packets transmitted, 4 received, 0% packet loss, time 3080ms
  rtt min/avg/max/mdev = 0.028/0.033/0.037/0.003 ms
  ```

- 测试

  ```shell
  curl https://test.com:9443/anything -k --cert ./client.cer --key ./client.key
  ```

  然后你将收到下面的响应体：

  ```shell
  {
    "args": {},
    "data": "",
    "files": {},
    "form": {},
    "headers": {
      "Accept": "*/*",
      "Host": "test.com",
      "User-Agent": "curl/7.81.0",
      "X-Amzn-Trace-Id": "Root=1-63256343-17e870ca1d8f72dc40b2c5a9",
      "X-Forwarded-Host": "test.com",
      "X-Ssl-Client-Fingerprint": "c1626ce3bca723f187d04e3757f1d000ca62d651",
      "X-Ssl-Client-S-Dn": "CN=CLIENT",
      "X-Ssl-Client-Serial": "5141CC6F5E2B4BA31746D7DBFE9BA81F069CF970"
    },
    "json": null,
    "method": "GET",
    "origin": "127.0.0.1",
    "url": "http://test.com/anything"
  }
  ```

由于我们在示例中配置了 `proxy-rewrite` 插件，我们可以看到响应体中包含上游收到的请求体，包含了正确数据。

## 总结

想了解更多有关 Apache APISIX 的 mTLS 功能介绍，可以阅读：[TLS 双向认证](../mtls.md)。
