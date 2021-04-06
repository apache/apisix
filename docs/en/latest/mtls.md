---
title: Mutual TLS authentication for Admin API
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

### Why use it

Mutual TLS authentication provides a better way to prevent unauthorized access to APISIX.

The clients will provide their certificates to the server and the server will check whether the cert is signed by the supplied CA and decide whether to serve the request.

### How to enable

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
