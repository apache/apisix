---
title: Mutual TLS Authentication
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

```yaml
  port_admin: 9180
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

```shell
curl --cacert /data/certs/mtls_ca.crt --key /data/certs/mtls_client.key --cert /data/certs/mtls_client.crt  https://admin.apisix.dev:9180/apisix/admin/routes -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1'
```

## etcd with mTLS

### How to configure

You need to [build APISIX-Openresty](./how-to-build.md#step-6-build-openresty-for-apache-apisix) and configure `etcd.tls` section if you want APISIX to work on an etcd cluster with mTLS enabled.

```yaml
etcd:
  tls:
    cert: /data/certs/etcd_client.pem       # path of certificate used by the etcd client
    key: /data/certs/etcd_client.key        # path of key used by the etcd client
```

If APISIX does not trust the CA certificate that used by etcd server, we need to set up the CA certificate.

```yaml
apisix:
  ssl:
    ssl_trusted_certificate: /path/to/certs/ca-certificates.crt       # path of CA certificate used by the etcd server
```

## Protect Route

### Why use it

Using mTLS is a way to verify clients cryptographically. It is useful and important in cases where you want to have encrypted and secure traffic in both directions.

### How to configure

When configuring `ssl`, use parameter `client.ca` and `client.depth` to configure the root CA that signing client certificates and the max length of certificate chain. Please refer to [Admin API](./admin-api.md#ssl) for details.

Here is an example Python script to create SSL with mTLS (id is `1`, changes admin API url if needed):

```py
#!/usr/bin/env python
# coding: utf-8
# save this file as ssl.py
import sys
# sudo pip install requests
import requests

if len(sys.argv) <= 4:
    print("bad argument")
    sys.exit(1)
with open(sys.argv[1]) as f:
    cert = f.read()
with open(sys.argv[2]) as f:
    key = f.read()
sni = sys.argv[3]
api_key = "edd1c9f034335f136f87ad84b625c8f1" # Change it

reqParam = {
    "cert": cert,
    "key": key,
    "snis": [sni],
}
if len(sys.argv) >= 5:
    print("Setting mTLS")
    reqParam["client"] = {}
    with open(sys.argv[4]) as f:
        clientCert = f.read()
        reqParam["client"]["ca"] = clientCert
    if len(sys.argv) >= 6:
        reqParam["client"]["depth"] = int(sys.argv[5])
resp = requests.put("http://127.0.0.1:9080/apisix/admin/ssl/1", json=reqParam, headers={
    "X-API-KEY": api_key,
})
print(resp.status_code)
print(resp.text)
```

Create SSL:

```bash
./ssl.py ./server.pem ./server.key 'mtls.test.com' ./client_ca.pem 10

# test it
curl --resolve 'mtls.test.com:<APISIX_HTTPS_PORT>:<APISIX_URL>' "https://<APISIX_URL>:<APISIX_HTTPS_PORT>/hello" -k --cert ./client.pem --key ./client.key
```

Please make sure that the SNI fits the certificate domain.

## mTLS Between APISIX and Upstream

### Why use it

Sometimes the upstream requires mTLS. In this situation, the APISIX acts as the client, it needs to provide client certificate to communicate with upstream.

### How to configure

When configuring `upstreams`, we could use parameter `tls.client_cert` and `tls.client_key` to configure the client certificate APISIX used to communicate with upstreams. Please refer to [Admin API](./admin-api.md#upstream) for details.

This feature requires APISIX to run on [APISIX-OpenResty](./how-to-build.md#step-6-build-openresty-for-apache-apisix).

Here is a similar Python script to patch a existed upstream with mTLS (changes admin API url if needed):

```python
#!/usr/bin/env python
# coding: utf-8
# save this file as patch_upstream_mtls.py
import sys
# sudo pip install requests
import requests

if len(sys.argv) <= 4:
    print("bad argument")
    sys.exit(1)
with open(sys.argv[2]) as f:
    cert = f.read()
with open(sys.argv[3]) as f:
    key = f.read()
id = sys.argv[1]
api_key = "edd1c9f034335f136f87ad84b625c8f1" # Change it

reqParam = {
    "tls": {
        "client_cert": cert,
        "client_key": key,
    },
}

resp = requests.patch("http://127.0.0.1:9080/apisix/admin/upstreams/"+id, json=reqParam, headers={
    "X-API-KEY": api_key,
})
print(resp.status_code)
print(resp.text)
```

Patch existed upstream with id `testmtls`:

```bash
./patch_upstream_mtls.py testmtls ./client.pem ./client.key
```
