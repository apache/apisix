---
title: 证书
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

`APISIX` 支持通过 TLS 扩展 SNI 实现加载特定的 SSL 证书以实现对 https 的支持。

SNI（Server Name Indication）是用来改善 SSL 和 TLS 的一项特性，它允许客户端在服务器端向其发送证书之前向服务器端发送请求的域名，服务器端根据客户端请求的域名选择合适的 SSL 证书发送给客户端。

### 单一域名指定

通常情况下一个 SSL 证书只包含一个静态域名，配置一个 `ssl` 参数对象，它包括 `cert`、`key`和`sni`三个属性，详细如下：

* `cert`：SSL 密钥对的公钥，pem 格式
* `key`：SSL 密钥对的私钥，pem 格式
* `snis`：SSL 证书所指定的一个或多个域名，注意在设置这个参数之前，你需要确保这个证书对应的私钥是有效的。

创建一个包含证书和密钥，单一域名 SNI 的 SSL 对象：

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/ssls/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
     "cert" : "'"$(cat t/certs/apisix.crt)"'",
     "key": "'"$(cat t/certs/apisix.key)"'",
     "snis": ["test.com"]
}'
```

创建路由：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -i -d '
{
    "uri": "/get",
    "hosts": ["test.com"],
    "methods": ["GET"],
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "httpbin.org": 1
        }
    }
}'
```

测试：

```shell
curl --resolve 'test.com:9443:127.0.0.1' https://test.com:9443/get -k -vvv

* Added test.com:9443:127.0.0.1 to DNS cache
* About to connect() to test.com port 9443 (#0)
*   Trying 127.0.0.1...
* Connected to test.com (127.0.0.1) port 9443 (#0)
* SSL connection using TLSv1.3 / TLS_AES_256_GCM_SHA384
* ALPN, server accepted to use h2
* Server certificate:
*   subject: C=CN; ST=GuangDong; L=ZhuHai; O=iresty; CN=test.com
*   start date: Jun 24 22:18:05 2019 GMT
*   expire date: May 31 22:18:05 2119 GMT
*   issuer: C=CN; ST=GuangDong; L=ZhuHai; O=iresty; CN=test.com
*   SSL certificate verify result: self-signed certificate (18), continuing anyway.
> GET /get HTTP/2
> Host: test.com:9443
> user-agent: curl/7.81.0
> accept: */*
```

### 泛域名

一个 SSL 证书的域名也可能包含泛域名，如 `*.test.com`，它代表所有以 `test.com` 结尾的域名都可以使用该证书。比如 `*.test.com`，可以匹配 `www.test.com`、`mail.test.com`。

以下是在 APISIX 中配置泛域名 SNI 的 SSL 证书的示例。

创建一个包含证书和密钥，泛域名 SNI 的 SSL 对象：

```shell
curl http://127.0.0.1:9180/apisix/admin/ssls/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
     "cert" : "'"$(cat t/certs/apisix.crt)"'",
     "key": "'"$(cat t/certs/apisix.key)"'",
     "snis": ["*.test.com"]
}'
```

创建路由：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -i -d '
{
    "uri": "/hello",
    "hosts": ["*.test.com"],
    "methods": ["GET"],
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```

测试：

```shell
curl --resolve 'www.test.com:9443:127.0.0.1' https://www.test.com:9443/get -k -vvv

* Added www.test.com:9443:127.0.0.1 to DNS cache
* Hostname www.test.com was found in DNS cache
*   Trying 127.0.0.1:9443...
* Connected to www.test.com (127.0.0.1) port 9443 (#0)
* SSL connection using TLSv1.3 / TLS_AES_256_GCM_SHA384
* ALPN, server accepted to use h2
* Server certificate:
*  subject: C=CN; ST=GuangDong; L=ZhuHai; O=iresty; CN=test.com
*  start date: Jun 24 22:18:05 2019 GMT
*  expire date: May 31 22:18:05 2119 GMT
*  issuer: C=CN; ST=GuangDong; L=ZhuHai; O=iresty; CN=test.com
*  SSL certificate verify result: self signed certificate (18), continuing anyway.
> GET /get HTTP/2
> Host: www.test.com:9443
> user-agent: curl/7.74.0
> accept: */*
```

### 多域名的情况

如果一个 SSL 证书包含多个独立域名，比如 `www.test.com` 和 `mail.test.com`，你可以把它们都放入 `snis` 数组中，就像这样：

```json
{
    "snis": ["www.test.com", "mail.test.com"]
}
```

### 单域名多证书的情况

如果你期望为一个域名配置多张证书，例如以此来同时支持使用 ECC 和 RSA
的密钥交换算法，那么你可以将额外的证书和私钥（第一张证书和其私钥依然使用 `cert` 和 `key`）配置在 `certs` 和 `keys` 中。

* `certs`：PEM 格式的 SSL 证书列表
* `keys`：PEM 格式的 SSL 证书私钥列表

`APISIX` 会将相同下标的证书和私钥配对使用，因此 `certs` 和 `keys` 列表的长度必须一致。

### 设置多个 CA 证书

APISIX 目前支持在多处设置 CA 证书，比如 [保护 Admin API](./mtls.md#保护-admin-api)，[保护 ETCD](./mtls.md#保护-etcd)，以及 [部署模式](../../en/latest/deployment-modes.md) 等。

在这些地方，使用 `ssl_trusted_certificate` 或 `trusted_ca_cert` 来配置 CA 证书，但是这些配置最终将转化为 OpenResty 的 [lua_ssl_trusted_certificate](https://github.com/openresty/lua-nginx-module#lua_ssl_trusted_certificate) 指令。

如果你需要在不同的地方指定不同的 CA 证书，你可以将这些 CA 证书制作成一个 CA bundle 文件，在需要用到 CA 证书的地方将配置指向这个文件。这样可以避免生成的 `lua_ssl_trusted_certificate` 存在多处并且互相覆盖的问题。

下面用一个完整的例子来展示如何在 APISIX 设置多个 CA 证书。

假设让 client 与 APISIX Admin API，APISIX 与 ETCD 之间都使用 mTLS 协议进行通信，目前有两张 CA 证书，分别是 `foo_ca.crt` 和 `bar_ca.crt`，用这两张 CA 证书各自签发 client 与 server 证书对，`foo_ca.crt` 及其签发的证书对用于保护 Admin API，`bar_ca.crt` 及其签发的证书对用于保护 ETCD。

下表详细列出这个示例所涉及到的配置及其作用：

| 配置              | 类型     | 用途                                                                                                               |
| -------------    | ------- | -----------------------------------------------------------------------------------------------------------        |
| foo_ca.crt       | CA 证书  | 签发客户端与 APISIX Admin API 进行 mTLS 通信所需的次级证书。                                                             |
| foo_client.crt   | 证书     | 由 `foo_ca.crt` 签发，客户端使用，访问 APISIX Admin API 时证明自身身份的证书。                                             |
| foo_client.key   | 密钥文件  | 由 `foo_ca.crt` 签发，客户端使用，访问 APISIX Admin API 所需的密钥文件。                                                  |
| foo_server.crt   | 证书     | 由 `foo_ca.crt` 签发，APISIX 使用，对应 `admin_api_mtls.admin_ssl_cert` 配置项。                                 |
| foo_server.key   | 密钥文件  | 由 `foo_ca.crt` 签发，APISIX 使用，对应 `admin_api_mtls.admin_ssl_cert_key` 配置项。                             |
| admin.apisix.dev | 域名     | 签发 `foo_server.crt` 证书时使用的 Common Name，客户端通过该域名访问 APISIX Admin API                                     |
| bar_ca.crt       | CA 证书  | 签发 APISIX 与 ETCD 进行 mTLS 通信所需的次级证书。                                                                       |
| bar_etcd.crt     | 证书     | 由 `bar_ca.crt` 签发，ETCD 使用，对应 ETCD 启动命令中的 `--cert-file` 选项。                                              |
| bar_etcd.key     | 密钥文件  | 由 `bar_ca.crt` 签发，ETCD 使用，对应 ETCD 启动命令中的 `--key-file` 选项。                                               |
| bar_apisix.crt   | 证书     | 由 `bar_ca.crt` 签发，APISIX 使用，对应 `etcd.tls.cert` 配置项。                                                         |
| bar_apisix.key   | 密钥文件  | 由 `bar_ca.crt` 签发，APISIX 使用，对应 `etcd.tls.key` 配置项。                                                          |
| etcd.cluster.dev | 域名     | 签发 `bar_etcd.crt` 证书时使用的 Common Name，APISIX 与 ETCD 进行 mTLS 通信时，使用该域名作为 SNI。对应 `etcd.tls.sni` 配置项。|
| apisix.ca-bundle | CA bundle | 由 `foo_ca.crt` 与 `bar_ca.crt` 合并而成，替代 `foo_ca.crt` 与 `bar_ca.crt`。                                |

1. 制作 CA bundle 文件

```shell
cat /path/to/foo_ca.crt /path/to/bar_ca.crt > apisix.ca-bundle
```

2. 启动 ETCD 集群，并开启客户端验证

先编写 `goreman` 配置，命名为 `Procfile-single-enable-mtls`，内容如下：

```text
# 运行 `go get github.com/mattn/goreman` 安装 goreman，用 goreman 执行以下命令：
etcd1: etcd --name infra1 --listen-client-urls https://127.0.0.1:12379 --advertise-client-urls https://127.0.0.1:12379 --listen-peer-urls http://127.0.0.1:12380 --initial-advertise-peer-urls http://127.0.0.1:12380 --initial-cluster-token etcd-cluster-1 --initial-cluster 'infra1=http://127.0.0.1:12380,infra2=http://127.0.0.1:22380,infra3=http://127.0.0.1:32380' --initial-cluster-state new --cert-file /path/to/bar_etcd.crt --key-file /path/to/bar_etcd.key --client-cert-auth --trusted-ca-file /path/to/apisix.ca-bundle
etcd2: etcd --name infra2 --listen-client-urls https://127.0.0.1:22379 --advertise-client-urls https://127.0.0.1:22379 --listen-peer-urls http://127.0.0.1:22380 --initial-advertise-peer-urls http://127.0.0.1:22380 --initial-cluster-token etcd-cluster-1 --initial-cluster 'infra1=http://127.0.0.1:12380,infra2=http://127.0.0.1:22380,infra3=http://127.0.0.1:32380' --initial-cluster-state new --cert-file /path/to/bar_etcd.crt --key-file /path/to/bar_etcd.key --client-cert-auth --trusted-ca-file /path/to/apisix.ca-bundle
etcd3: etcd --name infra3 --listen-client-urls https://127.0.0.1:32379 --advertise-client-urls https://127.0.0.1:32379 --listen-peer-urls http://127.0.0.1:32380 --initial-advertise-peer-urls http://127.0.0.1:32380 --initial-cluster-token etcd-cluster-1 --initial-cluster 'infra1=http://127.0.0.1:12380,infra2=http://127.0.0.1:22380,infra3=http://127.0.0.1:32380' --initial-cluster-state new --cert-file /path/to/bar_etcd.crt --key-file /path/to/bar_etcd.key --client-cert-auth --trusted-ca-file /path/to/apisix.ca-bundle
```

使用 `goreman` 来启动 ETCD 集群：

```shell
goreman -f Procfile-single-enable-mtls start > goreman.log 2>&1 &
```

3. 更新 `config.yaml`

```yaml title="conf/config.yaml"
deployment:
  admin:
    admin_key
      - name: admin
        key: edd1c9f034335f136f87ad84b625c8f1
        role: admin
    admin_listen:
      ip: 127.0.0.1
      port: 9180
    https_admin: true
    admin_api_mtls:
      admin_ssl_ca_cert: /path/to/apisix.ca-bundle
      admin_ssl_cert: /path/to/foo_server.crt
      admin_ssl_cert_key: /path/to/foo_server.key

apisix:
  ssl:
    ssl_trusted_certificate: /path/to/apisix.ca-bundle

deployment:
  role: traditional
  role_traditional:
    config_provider: etcd
  etcd:
    host:
      - "https://127.0.0.1:12379"
      - "https://127.0.0.1:22379"
      - "https://127.0.0.1:32379"
    tls:
      cert: /path/to/bar_apisix.crt
      key: /path/to/bar_apisix.key
      sni: etcd.cluster.dev
```

4. 测试 Admin API

启动 APISIX，如果 APISIX 启动成功，`logs/error.log` 中没有异常输出，表示 APISIX 与 ETCD 之间进行 mTLS 通信正常。

用 curl 模拟客户端，与 APISIX Admin API 进行 mTLS 通信，并创建一条路由：

```shell
curl -vvv \
    --resolve 'admin.apisix.dev:9180:127.0.0.1' https://admin.apisix.dev:9180/apisix/admin/routes/1 \
    --cert /path/to/foo_client.crt \
    --key /path/to/foo_client.key \
    --cacert /path/to/apisix.ca-bundle \
    -H "X-API-KEY: $admin_key" -X PUT -i -d '
{
    "uri": "/get",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "httpbin.org:80": 1
        }
    }
}'
```

如果输出以下 SSL 握手过程，表示 curl 与 APISIX Admin API 之间 mTLS 通信成功：

```shell
* TLSv1.3 (OUT), TLS handshake, Client hello (1):
* TLSv1.3 (IN), TLS handshake, Server hello (2):
* TLSv1.3 (IN), TLS handshake, Encrypted Extensions (8):
* TLSv1.3 (IN), TLS handshake, Request CERT (13):
* TLSv1.3 (IN), TLS handshake, Certificate (11):
* TLSv1.3 (IN), TLS handshake, CERT verify (15):
* TLSv1.3 (IN), TLS handshake, Finished (20):
* TLSv1.3 (OUT), TLS change cipher, Change cipher spec (1):
* TLSv1.3 (OUT), TLS handshake, Certificate (11):
* TLSv1.3 (OUT), TLS handshake, CERT verify (15):
* TLSv1.3 (OUT), TLS handshake, Finished (20):
* SSL connection using TLSv1.3 / TLS_AES_256_GCM_SHA384
```

5. 验证 APISIX 代理

```shell
curl http://127.0.0.1:9080/get -i

HTTP/1.1 200 OK
Content-Type: application/json
Content-Length: 298
Connection: keep-alive
Date: Tue, 26 Jul 2022 16:31:00 GMT
Access-Control-Allow-Origin: *
Access-Control-Allow-Credentials: true
Server: APISIX/2.14.1

……
```

APISIX 将请求代理到了上游 `httpbin.org` 的 `/get` 路径，并返回了 `HTTP/1.1 200 OK`。整个过程使用 CA bundle 替代 CA 证书是正常可用的。
