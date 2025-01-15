---
title: Mutual TLS Authentication
keywords:
  - Apache APISIX
  - Mutual TLS
  - mTLS
description: This document describes how you can secure communication to and within APISIX with mTLS.
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

## Protect Admin API

### Why use it

Mutual TLS authentication provides a better way to prevent unauthorized access to APISIX.

The clients will provide their certificates to the server and the server will check whether the cert is signed by the supplied CA and decide whether to serve the request.

### How to configure

1. Generate self-signed key pairs, including ca, server, client key pairs.

2. Modify configuration items in `conf/config.yaml`:

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

3. Run command:

```shell
apisix init
apisix reload
```

### How client calls

Please replace the following certificate paths and domain name with your real ones.

* Note: The same CA certificate as the server needs to be used *

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl --cacert /data/certs/mtls_ca.crt --key /data/certs/mtls_client.key --cert /data/certs/mtls_client.crt  https://admin.apisix.dev:9180/apisix/admin/routes -H "X-API-KEY: $admin_key"
```

## etcd with mTLS

### How to configure

You need to configure `etcd.tls` for APISIX to work on an etcd cluster with mTLS enabled as shown below:

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

If APISIX does not trust the CA certificate that used by etcd server, we need to set up the CA certificate.

```yaml title="conf/config.yaml"
apisix:
  ssl:
    ssl_trusted_certificate: /path/to/certs/ca-certificates.crt       # path of CA certificate used by the etcd server
```

## Protect Route

### Why use it

Using mTLS is a way to verify clients cryptographically. It is useful and important in cases where you want to have encrypted and secure traffic in both directions.

* Note: the mTLS protection only happens in HTTPS. If your route can also be accessed via HTTP, you should add additional protection in HTTP or disable the access via HTTP.*

### How to configure

We provide a [tutorial](./tutorials/client-to-apisix-mtls.md) that explains in detail how to configure mTLS between the client and APISIX.

When configuring `ssl`, use parameter `client.ca` and `client.depth` to configure the root CA that signing client certificates and the max length of certificate chain. Please refer to [Admin API](./admin-api.md#ssl) for details.

Here is an example shell script to create SSL with mTLS (id is `1`, changes admin API url if needed):

```shell
curl http://127.0.0.1:9180/apisix/admin/ssls/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
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

Send a request to verify:

```bash
curl --resolve 'mtls.test.com:<APISIX_HTTPS_PORT>:<APISIX_URL>' "https://<APISIX_URL>:<APISIX_HTTPS_PORT>/hello" -k --cert ./client.pem --key ./client.key

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

Please make sure that the SNI fits the certificate domain.

## mTLS Between APISIX and Upstream

### Why use it

Sometimes the upstream requires mTLS. In this situation, the APISIX acts as the client, it needs to provide client certificate to communicate with upstream.

### How to configure

When configuring `upstreams`, we could use parameter `tls.client_cert` and `tls.client_key` to configure the client certificate APISIX used to communicate with upstreams. Please refer to [Admin API](./admin-api.md#upstream) for details.

This feature requires APISIX to run on [APISIX-Runtime](./FAQ.md#how-do-i-build-the-apisix-runtime-environment).

Here is a similar shell script to patch a existed upstream with mTLS (changes admin API url if needed):

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
