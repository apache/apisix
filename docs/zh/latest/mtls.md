---
title: TLS 双向认证
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

## 保护 Admin API

### 为什么使用

双向认证提供了一种更好的方法来阻止未经授权的对 APISIX Admin API 的访问。

客户端需要向服务器提供证书，服务器将检查该客户端证书是否由受信的 CA 签名，并决定是否响应其请求。

### 如何配置

1. 生成自签证书对，包括 CA、server、client 证书对。

2. 修改 `conf/config.yaml` 中的配置项：

```yaml title="conf/config.yaml"
  admin_listen:
    ip: 127.0.0.1
    port: 9180
  https_admin: true

  admin_api_mtls:
    admin_ssl_ca_cert: "/data/certs/mtls_ca.crt"              # Path of your self-signed ca cert.
    admin_ssl_cert: "/data/certs/mtls_server.crt"             # Path of your self-signed server side cert.
    admin_ssl_cert_key: "/data/certs/mtls_server.key"         # Path of your self-signed server side key.
```

3. 执行命令，使配置生效：

```shell
apisix init
apisix reload
```

### 客户端如何调用

需要将证书文件的路径与域名按实际情况替换。

* 注意：提供的 CA 证书需要与服务端的相同。*

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl --cacert /data/certs/mtls_ca.crt --key /data/certs/mtls_client.key --cert /data/certs/mtls_client.crt  https://admin.apisix.dev:9180/apisix/admin/routes -H "X-API-KEY: $admin_key"
```

## 保护 ETCD

### 如何配置

你需要构建 [APISIX-runtime](./FAQ.md#如何构建-APISIX-runtime-环境？)，并且需要在配置文件中设定 `etcd.tls` 来使 ETCD 的双向认证功能正常工作。

```yaml title="conf/config.yaml"
deployment:
  role: traditional
  role_traditional:
    config_provider: etcd
  etcd:
    tls:
      cert: /data/certs/etcd_client.pem       # path of certificate used by the etcd client
      key: /data/certs/etcd_client.key        # path of key used by the etcd client
```

如果 APISIX 不信任 etcd server 使用的 CA 证书，我们需要设置 CA 证书。

```yaml title="conf/config.yaml"
apisix:
  ssl:
    ssl_trusted_certificate: /path/to/certs/ca-certificates.crt       # path of CA certificate used by the etcd server
```

## 保护路由

### 为什么使用

双向认证是一种密码学安全的验证客户端身份的手段。当你需要加密并保护流量的双向安全时很有用。

* 注意：双向认证只发生在 HTTPS 中。如果你的路由也可以通过 HTTP 访问，你应该在 HTTP 中添加额外的保护，或者禁止通过 HTTP 访问。*

### 如何配置

我们提供了一个[演示教程](./tutorials/client-to-apisix-mtls.md)，详细地讲解了如何配置客户端和 APISIX 之间的 mTLS。

在配置 `ssl` 资源时，同时需要配置 `client.ca` 和 `client.depth` 参数，分别代表为客户端证书签名的 CA 列表，和证书链的最大深度。可参考：[SSL API 文档](./admin-api.md#ssl)。

下面是一个可用于生成带双向认证配置的 SSL 资源的 shell 脚本示例（如果需要，可修改 API 地址、API Key 和 SSL 资源的 ID。）：

```shell
curl http://127.0.0.1:9180/apisix/admin/ssls/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
    "cert": "'"$(cat t/certs/mtls_server.crt)"'",
    "key": "'"$(cat t/certs/mtls_server.key)"'",
    "snis": [
        "admin.apisix.dev"
    ],
    "client": {
        "ca": "'"$(cat t/certs/mtls_ca.crt)"'",
        "depth": 10
    }
}'
```

测试：

```bash
curl -vvv --resolve 'admin.apisix.dev:9443:127.0.0.1' https://admin.apisix.dev:9443/hello --cert t/certs/mtls_client.crt --key t/certs/mtls_client.key --cacert t/certs/mtls_ca.crt

* Added admin.apisix.dev:9443:127.0.0.1 to DNS cache
* Hostname admin.apisix.dev was found in DNS cache
*   Trying 127.0.0.1:9443...
* Connected to admin.apisix.dev (127.0.0.1) port 9443 (#0)
* ALPN: offers h2
* ALPN: offers http/1.1
*  CAfile: t/certs/mtls_ca.crt
*  CApath: none
* [CONN-0-0][CF-SSL] (304) (OUT), TLS handshake, Client hello (1):
* [CONN-0-0][CF-SSL] (304) (IN), TLS handshake, Server hello (2):
* [CONN-0-0][CF-SSL] (304) (IN), TLS handshake, Unknown (8):
* [CONN-0-0][CF-SSL] (304) (IN), TLS handshake, Request CERT (13):
* [CONN-0-0][CF-SSL] (304) (IN), TLS handshake, Certificate (11):
* [CONN-0-0][CF-SSL] (304) (IN), TLS handshake, CERT verify (15):
* [CONN-0-0][CF-SSL] (304) (IN), TLS handshake, Finished (20):
* [CONN-0-0][CF-SSL] (304) (OUT), TLS handshake, Certificate (11):
* [CONN-0-0][CF-SSL] (304) (OUT), TLS handshake, CERT verify (15):
* [CONN-0-0][CF-SSL] (304) (OUT), TLS handshake, Finished (20):
* SSL connection using TLSv1.3 / AEAD-AES256-GCM-SHA384
* ALPN: server accepted h2
* Server certificate:
*  subject: C=cn; ST=GuangDong; L=ZhuHai; CN=admin.apisix.dev; OU=ops
*  start date: Dec  1 10:17:24 2022 GMT
*  expire date: Aug 18 10:17:24 2042 GMT
*  subjectAltName: host "admin.apisix.dev" matched cert's "admin.apisix.dev"
*  issuer: C=cn; ST=GuangDong; L=ZhuHai; CN=ca.apisix.dev; OU=ops
*  SSL certificate verify ok.
* Using HTTP2, server supports multiplexing
* Copying HTTP/2 data in stream buffer to connection buffer after upgrade: len=0
* h2h3 [:method: GET]
* h2h3 [:path: /hello]
* h2h3 [:scheme: https]
* h2h3 [:authority: admin.apisix.dev:9443]
* h2h3 [user-agent: curl/7.87.0]
* h2h3 [accept: */*]
* Using Stream ID: 1 (easy handle 0x13000bc00)
> GET /hello HTTP/2
> Host: admin.apisix.dev:9443
> user-agent: curl/7.87.0
> accept: */*
```

注意，测试时使用的域名需要符合证书的参数。

## APISIX 与上游间的双向认证

### 为什么使用

有时候上游的服务启用了双向认证。在这种情况下，APISIX 作为上游服务的客户端，需要提供客户端证书来正常与其进行通信。

### 如何配置

在配置 upstream 资源时，可以使用参数 `tls.client_cert` 和 `tls.client_key` 来配置 APISIX 用于与上游进行通讯时使用的证书。可参考 [Upstream API 文档](./admin-api.md#upstream)。

该功能需要 APISIX 运行在 [APISIX-Runtime](./FAQ.md#如何构建-apisix-runtime-环境) 上。

下面是一个与配置 SSL 时相似的 shell 脚本，可为一个已存在的 upstream 资源配置双向认证。

```shell
curl http://127.0.0.1:9180/apisix/admin/upstreams/1 \
-H "X-API-KEY: $admin_key" -X PATCH -d '
{
    "tls": {
        "client_cert": "'"$(cat t/certs/mtls_client.crt)"'",
        "client_key": "'"$(cat t/certs/mtls_client.key)"'"
    }
}'
```
