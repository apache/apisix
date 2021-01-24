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

[Chinese](zh-cn/plugin-interceptors.md)

## Plugin interceptors

Some plugins will register API to serve their purposes.

Since these API are not added as regular [Route](admin-api.md), we can't add
plugins to protect them. To solve the problem, we add a new concept called 'interceptors'
to run rules to protect them.

Here is an example to limit the access of `/apisix/prometheus/metrics` (a route introduced via plugin prometheus)
to clients in `10.0.0.0/24`:

```shell
$ curl http://127.0.0.1:9080/apisix/admin/plugin_metadata/prometheus -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -i -X PUT -d '
{
    "interceptors": [
        {
            "name": "ip-restriction",
            "conf": {
                "whitelist": ["10.0.0.0/24"]
            }
        }
    ]
}'
```

You can see that the interceptors are configured like the plugins. The `name` is
the name of plugin which you want to run and the `conf` is the configuration of the
plugin.

Currently we only support a subset of plugins which can be run as interceptors.

Supported interceptors:

* [ip-restriction](./plugins/ip-restriction.md)
