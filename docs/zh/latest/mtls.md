---
title: 双向认证
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

### 为什么使用

双向认证可以更好的防止未经授权访问 APISIX ，客户端将向服务器提供其证书，服务器将检查证书是否由提供的 CA 签名并决定是否响应请求。

### 如何开启

1. 生成自签证书对，包括 ca、server、client 证书对。

2. 修改 `conf/config.yaml` 中的配置项:

```yaml
  port_admin: 9180
  https_admin: true

  mtls:
    enable: true               # Enable or disable mTLS. Enable depends on `port_admin` and `https_admin`.
    ca_cert: "/data/certs/mtls_ca.crt"                 # Path of your self-signed CA cert.
    server_key: "/data/certs/mtls_server.key"          # Path of your self-signed server side cert.
    server_cert: "/data/certs/mtls_server.crt"         # Path of your self-signed server side key.
```

3. 执行命令:

```shell
apisix init
apisix reload
```

### 客户端如何调用

请将以下证书及域名替换为您的真实内容。

* 注意：需要和服务器使用相同的 CA 证书 *

```shell
curl --cacert /data/certs/mtls_ca.crt --key /data/certs/mtls_client.key --cert /data/certs/mtls_client.crt  https://admin.apisix.dev:9180/apisix/admin/routes -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1'
```
