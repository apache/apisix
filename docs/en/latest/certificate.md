---
title: Certificate
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

`APISIX` supports to load multiple SSL certificates by TLS extension Server Name Indication (SNI).

### Single SNI

It is most common for an SSL certificate to contain only one domain. We can create an `ssl` object. Here is a simple case, creates a `ssl` object and `route` object.

* `cert`: PEM-encoded public certificate of the SSL key pair.
* `key`: PEM-encoded private key of the SSL key pair.
* `snis`: Hostname(s) to associate with this certificate as SNIs. To set this attribute this certificate must have a valid private key associated with it.

The following is an example of configuring an SSL certificate with a single SNI in APISIX.

Create an SSL object with the certificate and key valid for the SNI:

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

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

Create a Router object:

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

Send a request to verify:

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

### wildcard SNI

An SSL certificate could also be valid for a wildcard domain like `*.test.com`, which means it is valid for any domain of that pattern, including `www.test.com` and `mail.test.com`.

The following is an example of configuring an SSL certificate with a wildcard SNI in APISIX.

Create an SSL object with the certificate and key valid for the SNI:

```shell
curl http://127.0.0.1:9180/apisix/admin/ssls/1 \
 -H "X-API-KEY: $admin_key" -X PUT -d '
 {
      "cert" : "'"$(cat t/certs/apisix.crt)"'",
      "key": "'"$(cat t/certs/apisix.key)"'",
      "snis": ["*.test.com"]
 }'
```

Create a Router object:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -i -d '
{
    "uri": "/get",
    "hosts": ["*.test.com"],
    "methods": ["GET"],
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "httpbin.org": 1
        }
    }
}'
```

Send a request to verify:

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

### multiple domain

If your SSL certificate may contain more than one domain, like `www.test.com` and `mail.test.com`, then you can add them into the `snis` array. For example:

```json
{
    "snis": ["www.test.com", "mail.test.com"]
}
```

### multiple certificates for a single domain

If you want to configure multiple certificate for a single domain, for
instance, supporting both the
[ECC](https://en.wikipedia.org/wiki/Elliptic-curve_cryptography)
and RSA key-exchange algorithm, then just configure the extra certificates (the
first certificate and private key should be still put in `cert` and `key`) and
private keys by `certs` and `keys`.

* `certs`: PEM-encoded certificate array.
* `keys`: PEM-encoded private key array.

`APISIX` will pair certificate and private key with the same indice as a SSL key
pair. So the length of `certs` and `keys` must be same.

### set up multiple CA certificates

APISIX currently uses CA certificates in several places, such as [Protect Admin API](./mtls.md#protect-admin-api), [etcd with mTLS](./mtls.md#etcd-with-mtls), and [Deployment Modes](./deployment-modes.md).

In these places, `ssl_trusted_certificate` or `trusted_ca_cert` will be used to set up the CA certificate, but these configurations will eventually be translated into [lua_ssl_trusted_certificate](https://github.com/openresty/lua-nginx-module#lua_ssl_trusted_certificate) directive in OpenResty.

If you need to set up different CA certificates in different places, then you can package these CA certificates into a CA bundle file and point to this file when you need to set up CAs. This will avoid the problem that the generated `lua_ssl_trusted_certificate` has multiple locations and overwrites each other.

The following is a complete example to show how to set up multiple CA certificates in APISIX.

Suppose we let client and APISIX Admin API, APISIX and ETCD communicate with each other using mTLS protocol, and currently there are two CA certificates, `foo_ca.crt` and `bar_ca.crt`, and use each of these two CA certificates to issue client and server certificate pairs, `foo_ca.crt` and its issued certificate pair are used to protect Admin API, and `bar_ca.crt` and its issued certificate pair are used to protect ETCD.

The following table details the configurations involved in this example and what they do:

| Configuration    | Type     | Description                                                                                                                                                                  |
| -------------    | -------  | -------------------------------------------------------------------------------------------------------------------------------------------------------------                |
| foo_ca.crt       | CA cert  | Issues the secondary certificate required for the client to communicate with the APISIX Admin API over mTLS.                                                                 |
| foo_client.crt   | cert     | A certificate issued by `foo_ca.crt` and used by the client to prove its identity when accessing the APISIX Admin API.                                                       |
| foo_client.key   | key      | Issued by `foo_ca.crt`, used by the client, the key file required to access the APISIX Admin API.                                                                            |
| foo_server.crt   | cert     | Issued by `foo_ca.crt`, used by APISIX, corresponding to the `admin_api_mtls.admin_ssl_cert` configuration entry.                                                     |
| foo_server.key   | key      | Issued by `foo_ca.crt`, used by APISIX, corresponding to the `admin_api_mtls.admin_ssl_cert_key` configuration entry.                                                 |
| admin.apisix.dev | doname   | Common Name used in issuing `foo_server.crt` certificate, through which the client accesses APISIX Admin API                                                                 |
| bar_ca.crt       | CA cert  | Issues the secondary certificate required for APISIX to communicate with ETCD over mTLS.                                                                                     |
| bar_etcd.crt     | cert     | Issued by `bar_ca.crt` and used by ETCD, corresponding to the `-cert-file` option in the ETCD startup command.                                                               |
| bar_etcd.key     | key      | Issued by `bar_ca.crt` and used by ETCD, corresponding to the `--key-file` option in the ETCD startup command.                                                               |
| bar_apisix.crt   | cert     | Issued by `bar_ca.crt`, used by APISIX, corresponding to the `etcd.tls.cert` configuration entry.                                                                            |
| bar_apisix.key   | key      | Issued by `bar_ca.crt`, used by APISIX, corresponding to the `etcd.tls.key` configuration entry.                                                                             |
| etcd.cluster.dev | key      | Common Name used in issuing `bar_etcd.crt` certificate, which is used as SNI when APISIX communicates with ETCD over mTLS. corresponds to `etcd.tls.sni` configuration item. |
| apisix.ca-bundle | CA bundle | Merged from `foo_ca.crt` and `bar_ca.crt`, replacing `foo_ca.crt` and `bar_ca.crt`.                                                                                         |

1. Create CA bundle files

```shell
cat /path/to/foo_ca.crt /path/to/bar_ca.crt > apisix.ca-bundle
```

2. Start the ETCD cluster and enable client authentication

Start by writing a `goreman` configuration named `Procfile-single-enable-mtls`, the content as:

```text
# Use goreman to run `go get github.com/mattn/goreman`
etcd1: etcd --name infra1 --listen-client-urls https://127.0.0.1:12379 --advertise-client-urls https://127.0.0.1:12379 --listen-peer-urls http://127.0.0.1:12380 --initial-advertise-peer-urls http://127.0.0.1:12380 --initial-cluster-token etcd-cluster-1 --initial-cluster 'infra1=http://127.0.0.1:12380,infra2=http://127.0.0.1:22380,infra3=http://127.0.0.1:32380' --initial-cluster-state new --cert-file /path/to/bar_etcd.crt --key-file /path/to/bar_etcd.key --client-cert-auth --trusted-ca-file /path/to/apisix.ca-bundle
etcd2: etcd --name infra2 --listen-client-urls https://127.0.0.1:22379 --advertise-client-urls https://127.0.0.1:22379 --listen-peer-urls http://127.0.0.1:22380 --initial-advertise-peer-urls http://127.0.0.1:22380 --initial-cluster-token etcd-cluster-1 --initial-cluster 'infra1=http://127.0.0.1:12380,infra2=http://127.0.0.1:22380,infra3=http://127.0.0.1:32380' --initial-cluster-state new --cert-file /path/to/bar_etcd.crt --key-file /path/to/bar_etcd.key --client-cert-auth --trusted-ca-file /path/to/apisix.ca-bundle
etcd3: etcd --name infra3 --listen-client-urls https://127.0.0.1:32379 --advertise-client-urls https://127.0.0.1:32379 --listen-peer-urls http://127.0.0.1:32380 --initial-advertise-peer-urls http://127.0.0.1:32380 --initial-cluster-token etcd-cluster-1 --initial-cluster 'infra1=http://127.0.0.1:12380,infra2=http://127.0.0.1:22380,infra3=http://127.0.0.1:32380' --initial-cluster-state new --cert-file /path/to/bar_etcd.crt --key-file /path/to/bar_etcd.key --client-cert-auth --trusted-ca-file /path/to/apisix.ca-bundle
```

Use `goreman` to start the ETCD cluster:

```shell
goreman -f Procfile-single-enable-mtls start > goreman.log 2>&1 &
```

3. Update `config.yaml`

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

4. Test APISIX Admin API

Start APISIX, if APISIX starts successfully and there is no abnormal output in `logs/error.log`, it means that mTLS communication between APISIX and ETCD is normal.

Use curl to simulate a client, communicate with APISIX Admin API with mTLS, and create a route:

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

A successful mTLS communication between curl and the APISIX Admin API is indicated if the following SSL handshake process is output:

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

5. Verify APISIX proxy

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

...
```

APISIX proxied the request to the `/get` path of the upstream `httpbin.org` and returned `HTTP/1.1 200 OK`. The whole process is working fine using CA bundle instead of CA certificate.
