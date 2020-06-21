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

[Chinese](zh-cn/two-side-auth-with-ssl.md)

## Enable client-to-server authentication with ssl certificates

1. Generate self-signed key pairs, including ca, server, client key pairs.

2. Replace `cert/two-side-ca.crt` with the ca cert just generated. And replace `cert/two-side-client.crt` and `cert/two-side-client.key` in the same way.

3. Modify configuration items in `conf/config.yaml`:
```yaml
  port_admin: 9180
  https_admin: true

  ssl:
    verify_client: true   
```

4. Run command:
```shell
apisix init
apisix reload
```