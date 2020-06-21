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

[English](../two-side-auth-with-ssl.md)

## 开启双向认证

1. 生成自签证书对，包括 ca、server、client 证书对。

2. 用刚刚生成的证书相应的替换 `cert/two-side-ca.crt`、`cert/two-side-client.crt` 和 `cert/two-side-client.key`。 

3. 修改 `conf/config.yaml` 中的配置项:
```yaml
  port_admin: 9180
  https_admin: true

  ssl:
    verify_client: true   
```

4. 执行命令:
```shell
apisix init
apisix reload
```