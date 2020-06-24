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

[Chinese](zh-cn/mtls.md)

## Enable mutual TLS authentication

1. Generate self-signed key pairs, including ca, server, client key pairs.

2. Modify configuration items in `conf/config.yaml`:

```yaml
  port_admin: 9180
  https_admin: true

  mtls:
    enable: true               # Enable or disable mTLS. Enable depends on `port_admin` and `https_admin`.
    ca_cert: "/data/certs/mtls_ca.crt"                 # Path of your self-signed ca cert.
    server_key: "/data/certs/mtls_server.key"          # Path of your self-signed server side cert.
    server_cert: "/data/certs/mtls_server.crt"         # Path of your self-signed server side key.
```

3. Run command:

```shell
apisix init
apisix reload
```
