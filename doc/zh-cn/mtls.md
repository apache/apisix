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

[English](../mtls.md)

## 开启双向认证

1. 生成自签证书对，包括 ca、server、client 证书对。

2. 修改 `conf/config.yaml` 中的配置项:
```yaml
  port_admin: 9180
  https_admin: true

  mtls:
    enable: true               # Enable or disable mTLS. Enable depends on `port_admin` and `https_admin`.
    ca_cert: "/data/certs/mtls_ca.crt"                 # Path of your self-signed ca cert.
    server_key: "/data/certs/mtls_server.key"          # Path of your self-signed server side cert.
    server_cert: "/data/certs/mtls_server.crt"         # Path of your self-signed server side key.
```

3. 执行命令:
```shell
apisix init
apisix reload
```
