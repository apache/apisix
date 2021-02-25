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

## Plugin interceptors

有些插件为实现它的功能会注册额外的接口。

由于这些接口不是通过 admin API 添加的，所以没办法像管理 Route 那样管理它们。为了能够保护这些接口不被利用，我们引入了 interceptors 的概念。

下面是通过 interceptors 来保护由 prometheus 插件引入的 `/apisix/prometheus/metrics` 接口，限定只能由 `10.0.0.0/24` 网段的用户访问：

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

我们能看到配置 interceptors 就像配置 plugin 一样：name 是 interceptor 的名称，而 conf 是它的配置。

当前我们只支持一部分插件作为 interceptor 运行。

支持的 interceptor：

* [ip-restriction](./plugins/ip-restriction.md)
