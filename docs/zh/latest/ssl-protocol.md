---
title: SSL 协议
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

`APISIX` 支持 TLS 协议，还支持动态的为每一个 SNI 指定不同的 TLS 协议版本。

**为了安全考虑，APISIX 默认使用的加密套件不支持 TLSv1.1 以及更低的版本。**
**如果你需要启用 TLSv1.1 协议，请在 config.yaml 的配置项 apisix.ssl.ssl_ciphers 增加 TLSv1.1 协议所支持的加密套件。**

## ssl_protocols 配置

### 静态配置

静态配置中 config.yaml 的 ssl_protocols 参数会作用于 APISIX 全局，但是不能动态修改，仅当匹配的 SSL 资源未设置 `ssl_protocols`，静态配置才会生效。

```yaml
apisix:
  ssl:
    ssl_protocols: TLSv1.2 TLSv1.3 # default TLSv1.2 TLSv1.3
```

### 动态配置

使用 ssl 资源中 ssl_protocols 字段动态的为每一个 SNI 指定不同的 TLS 协议版本。

指定 test.com 域名使用 TLSv1.2 TLSv1.3 协议版本：

```bash
{
    "cert": "$cert",
    "key": "$key",
    "snis": ["test.com"],
    "ssl_protocols": [
        "TLSv1.2",
        "TLSv1.3"
    ]
}
```

### 注意事项

- 动态配置优先级比静态配置更高，当 ssl 资源配置项 ssl_protocols 不为空时 静态配置将会被覆盖。
- 静态配置作用于全局需要重启 apisix 才能生效。
- 动态配置可细粒度的控制每个 SNI 的 TLS 协议版本，并且能够动态修改，相比于静态配置更加灵活。

## 使用示例

### 如何指定 TLSv1.1 协议

存在一些老旧的客户端，仍然采用较低级别的 TLSv1.1 协议版本，而新的产品则使用较高安全级别的 TLS 协议版本。如果让新产品支持 TLSv1.1 可能会带来一些安全隐患。为了保证 API 的安全性，我们需要在协议版本之间进行灵活转换。
例如：test.com 是老旧客户端所使用的域名，需要将其配置为 TLSv1.1 而 test2.com 属于新产品，同时支持了 TLSv1.2，TLSv1.3 协议。

1. config.yaml 配置。

```yaml
apisix:
  ssl:
    ssl_protocols: TLSv1.3
    # ssl_ciphers is for reference only
    ssl_ciphers: ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-SHA:ECDHE-ECDSA-AES256-SHA:DHE-RSA-AES256-SHA:DHE-DSS-AES256-SHA
```

2. 为 test.com 域名指定 TLSv1.1 协议版本。

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```bash
curl http://127.0.0.1:9180/apisix/admin/ssls/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
     "cert" : "'"$(cat server.crt)"'",
     "key": "'"$(cat server.key)"'",
     "snis": ["test.com"],
     "ssl_protocols": [
         "TLSv1.1"
     ]
}'
```

3. 为 test.com 创建 SSL 对象，未指定 TLS 协议版本，将默认使用静态配置。

```bash
curl http://127.0.0.1:9180/apisix/admin/ssls/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
     "cert" : "'"$(cat server2.crt)"'",
     "key": "'"$(cat server2.key)"'",
     "snis": ["test2.com"]
}'
```

4. 访问验证

使用 TLSv1.3 访问 test.com 失败：

```shell
$ curl --tls-max 1.3 --tlsv1.3  https://test.com:9443 -v -k -I
*   Trying 127.0.0.1:9443...
* Connected to test.com (127.0.0.1) port 9443 (#0)
* ALPN, offering h2
* ALPN, offering http/1.1
* successfully set certificate verify locations:
*  CAfile: /etc/ssl/certs/ca-certificates.crt
*  CApath: /etc/ssl/certs
* TLSv1.3 (OUT), TLS handshake, Client hello (1):
* TLSv1.3 (IN), TLS alert, protocol version (582):
* error:1409442E:SSL routines:ssl3_read_bytes:tlsv1 alert protocol version
* Closing connection 0
curl: (35) error:1409442E:SSL routines:ssl3_read_bytes:tlsv1 alert protocol version
```

使用 TLSv1.1 访问 test.com 成功：

```shell
$ curl --tls-max 1.1 --tlsv1.1  https://test.com:9443 -v -k -I
*   Trying 127.0.0.1:9443...
* Connected to test.com (127.0.0.1) port 9443 (#0)
* ALPN, offering h2
* ALPN, offering http/1.1
* successfully set certificate verify locations:
*  CAfile: /etc/ssl/certs/ca-certificates.crt
*  CApath: /etc/ssl/certs
* TLSv1.1 (OUT), TLS handshake, Client hello (1):
* TLSv1.1 (IN), TLS handshake, Server hello (2):
* TLSv1.1 (IN), TLS handshake, Certificate (11):
* TLSv1.1 (IN), TLS handshake, Server key exchange (12):
* TLSv1.1 (IN), TLS handshake, Server finished (14):
* TLSv1.1 (OUT), TLS handshake, Client key exchange (16):
* TLSv1.1 (OUT), TLS change cipher, Change cipher spec (1):
* TLSv1.1 (OUT), TLS handshake, Finished (20):
* TLSv1.1 (IN), TLS handshake, Finished (20):
* SSL connection using TLSv1.1 / ECDHE-RSA-AES256-SHA
```

使用 TLSv1.3 访问 test2.com 成功：

```shell
$ curl --tls-max 1.3 --tlsv1.3  https://test2.com:9443 -v -k -I
*   Trying 127.0.0.1:9443...
* Connected to test2.com (127.0.0.1) port 9443 (#0)
* ALPN, offering h2
* ALPN, offering http/1.1
* successfully set certificate verify locations:
*  CAfile: /etc/ssl/certs/ca-certificates.crt
*  CApath: /etc/ssl/certs
* TLSv1.3 (OUT), TLS handshake, Client hello (1):
* TLSv1.3 (IN), TLS handshake, Server hello (2):
* TLSv1.3 (IN), TLS handshake, Encrypted Extensions (8):
* TLSv1.3 (IN), TLS handshake, Certificate (11):
* TLSv1.3 (IN), TLS handshake, CERT verify (15):
* TLSv1.3 (IN), TLS handshake, Finished (20):
* TLSv1.3 (OUT), TLS change cipher, Change cipher spec (1):
* TLSv1.3 (OUT), TLS handshake, Finished (20):
* SSL connection using TLSv1.3 / TLS_AES_256_GCM_SHA384
```

使用 TLSv1.1 访问 test2.com 失败：

```shell
curl --tls-max 1.1 --tlsv1.1  https://test2.com:9443 -v -k -I
*   Trying 127.0.0.1:9443...
* Connected to test2.com (127.0.0.1) port 9443 (#0)
* ALPN, offering h2
* ALPN, offering http/1.1
* successfully set certificate verify locations:
*  CAfile: /etc/ssl/certs/ca-certificates.crt
*  CApath: /etc/ssl/certs
* TLSv1.1 (OUT), TLS handshake, Client hello (1):
* TLSv1.1 (IN), TLS alert, protocol version (582):
* error:1409442E:SSL routines:ssl3_read_bytes:tlsv1 alert protocol version
* Closing connection 0
curl: (35) error:1409442E:SSL routines:ssl3_read_bytes:tlsv1 alert protocol version
```

### 证书关联多个域名，但域名之间使用不同的 TLS 协议

有时候，我们可能会遇到这样一种情况，即一个证书关联了多个域名，但是它们需要使用不同的 TLS 协议来保证安全性。例如 test.com 域名需要使用 TlSv1.2 协议，而 test2.com 域名则需要使用 TLSv1.3 协议。在这种情况下，我们不能简单地为所有的域名创建一个 SSL 对象，而是需要为每个域名单独创建一个 SSL 对象，并指定相应的协议版本。这样，我们就可以根据不同的域名和协议版本来进行正确的 SSL 握手和加密通信。示例如下：

1. 使用证书为 test.com 创建 ssl 对象，并指定 TLSv1.2 协议。

```bash
curl http://127.0.0.1:9180/apisix/admin/ssls/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
     "cert" : "'"$(cat server.crt)"'",
     "key": "'"$(cat server.key)"'",
     "snis": ["test.com"],
     "ssl_protocols": [
         "TLSv1.2"
     ]
}'
```

2. 使用与 test.com 同一证书，为 test2.com 创建 ssl 对象，并指定 TLSv1.3 协议。

```bash
curl http://127.0.0.1:9180/apisix/admin/ssls/2 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
     "cert" : "'"$(cat server.crt)"'",
     "key": "'"$(cat server.key)"'",
     "snis": ["test2.com"],
     "ssl_protocols": [
         "TLSv1.3"
     ]
}'
```

3. 访问验证

使用 TLSv1.2 访问 test.com 成功：

```shell
$ curl --tls-max 1.2 --tlsv1.2  https://test.com:9443 -v -k -I
*   Trying 127.0.0.1:9443...
* Connected to test.com (127.0.0.1) port 9443 (#0)
* ALPN, offering h2
* ALPN, offering http/1.1
* successfully set certificate verify locations:
*  CAfile: /etc/ssl/certs/ca-certificates.crt
*  CApath: /etc/ssl/certs
* TLSv1.2 (OUT), TLS handshake, Client hello (1):
* TLSv1.2 (IN), TLS handshake, Server hello (2):
* TLSv1.2 (IN), TLS handshake, Certificate (11):
* TLSv1.2 (IN), TLS handshake, Server key exchange (12):
* TLSv1.2 (IN), TLS handshake, Server finished (14):
* TLSv1.2 (OUT), TLS handshake, Client key exchange (16):
* TLSv1.2 (OUT), TLS change cipher, Change cipher spec (1):
* TLSv1.2 (OUT), TLS handshake, Finished (20):
* TLSv1.2 (IN), TLS handshake, Finished (20):
* SSL connection using TLSv1.2 / ECDHE-RSA-AES128-GCM-SHA256
* ALPN, server accepted to use h2
* Server certificate:
*  subject: C=AU; ST=Some-State; O=Internet Widgits Pty Ltd; CN=test.com
*  start date: Jul 20 15:50:08 2023 GMT
*  expire date: Jul 17 15:50:08 2033 GMT
*  issuer: C=AU; ST=Some-State; O=Internet Widgits Pty Ltd; CN=test.com
*  SSL certificate verify result: EE certificate key too weak (66), continuing anyway.
* Using HTTP2, server supports multi-use
* Connection state changed (HTTP/2 confirmed)
* Copying HTTP/2 data in stream buffer to connection buffer after upgrade: len=0
* Using Stream ID: 1 (easy handle 0x5608905ee2e0)
> HEAD / HTTP/2
> Host: test.com:9443
> user-agent: curl/7.74.0
> accept: */*

```

使用 TLSv1.3 协议访问 test.com 失败：

```shell
$ curl --tls-max 1.3 --tlsv1.3  https://test.com:9443 -v -k -I
*   Trying 127.0.0.1:9443...
* Connected to test.com (127.0.0.1) port 9443 (#0)
* ALPN, offering h2
* ALPN, offering http/1.1
* successfully set certificate verify locations:
*  CAfile: /etc/ssl/certs/ca-certificates.crt
*  CApath: /etc/ssl/certs
* TLSv1.3 (OUT), TLS handshake, Client hello (1):
* TLSv1.3 (IN), TLS alert, protocol version (582):
* error:1409442E:SSL routines:ssl3_read_bytes:tlsv1 alert protocol version
* Closing connection 0
curl: (35) error:1409442E:SSL routines:ssl3_read_bytes:tlsv1 alert protocol version

```

使用 TLSv1.3 协议访问 test2.com 成功：

```shell
$ curl --tls-max 1.3 --tlsv1.3  https://test2.com:9443 -v -k -I
*   Trying 127.0.0.1:9443...
* Connected to test2.com (127.0.0.1) port 9443 (#0)
* ALPN, offering h2
* ALPN, offering http/1.1
* successfully set certificate verify locations:
*  CAfile: /etc/ssl/certs/ca-certificates.crt
*  CApath: /etc/ssl/certs
* TLSv1.3 (OUT), TLS handshake, Client hello (1):
* TLSv1.3 (IN), TLS handshake, Server hello (2):
* TLSv1.3 (IN), TLS handshake, Encrypted Extensions (8):
* TLSv1.3 (IN), TLS handshake, Certificate (11):
* TLSv1.3 (IN), TLS handshake, CERT verify (15):
* TLSv1.3 (IN), TLS handshake, Finished (20):
* TLSv1.3 (OUT), TLS change cipher, Change cipher spec (1):
* TLSv1.3 (OUT), TLS handshake, Finished (20):
* SSL connection using TLSv1.3 / TLS_AES_256_GCM_SHA384
* ALPN, server accepted to use h2
* Server certificate:
*  subject: C=AU; ST=Some-State; O=Internet Widgits Pty Ltd; CN=test2.com
*  start date: Jul 20 16:05:47 2023 GMT
*  expire date: Jul 17 16:05:47 2033 GMT
*  issuer: C=AU; ST=Some-State; O=Internet Widgits Pty Ltd; CN=test2.com
*  SSL certificate verify result: EE certificate key too weak (66), continuing anyway.
* Using HTTP2, server supports multi-use
* Connection state changed (HTTP/2 confirmed)
* Copying HTTP/2 data in stream buffer to connection buffer after upgrade: len=0
* Using Stream ID: 1 (easy handle 0x55569cbe42e0)
> HEAD / HTTP/2
> Host: test2.com:9443
> user-agent: curl/7.74.0
> accept: */*
>
* TLSv1.3 (IN), TLS handshake, Newsession Ticket (4):
* TLSv1.3 (IN), TLS handshake, Newsession Ticket (4):
* old SSL session ID is stale, removing
```

使用 TLSv1.2 协议访问 test2.com 失败：

```shell
$ curl --tls-max 1.2 --tlsv1.2  https://test2.com:9443 -v -k -I
*   Trying 127.0.0.1:9443...
* Connected to test2.com (127.0.0.1) port 9443 (#0)
* ALPN, offering h2
* ALPN, offering http/1.1
* successfully set certificate verify locations:
*  CAfile: /etc/ssl/certs/ca-certificates.crt
*  CApath: /etc/ssl/certs
* TLSv1.2 (OUT), TLS handshake, Client hello (1):
* TLSv1.2 (IN), TLS alert, protocol version (582):
* error:1409442E:SSL routines:ssl3_read_bytes:tlsv1 alert protocol version
* Closing connection 0
curl: (35) error:1409442E:SSL routines:ssl3_read_bytes:tlsv1 alert protocol version
```
