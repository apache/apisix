---
title: Plugin Config
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

如果你想要复用一组通用的插件配置，你可以把它们提取成一个 Plugin config，并绑定到对应的路由上。

举个例子，你可以这么做：

```shell
# 创建 Plugin config
$ curl http://127.0.0.1:9080/apisix/admin/plugin_configs/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -i -d '
{
    "desc": "吾乃插件配置1",
    "plugins": {
        "limit-count": {
            "count": 2,
            "time_window": 60,
            "rejected_code": 503
        }
    }
}'

# 绑定到路由上
$ curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -i -d '
{
    "uris": ["/index.html"],
    "plugin_config_id": 1,
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "39.97.63.215:80": 1
        }
    }
}'
```

如果找不到对应的 Plugin config，该路由上的请求会报 503 错误。

如果这个路由已经配置了 `plugins`，那么 Plugin config 里面的插件配置会合并进去。
相同的插件会覆盖掉 `plugins` 原有的插件。

举个例子：

```
{
    "desc": "吾乃插件配置1",
    "plugins": {
        "ip-restriction": {
            "whitelist": [
                "127.0.0.0/24",
                "113.74.26.106"
            ]
        },
        "limit-count": {
            "count": 2,
            "time_window": 60,
            "rejected_code": 503
        }
    }
}
```

加上

```
{
    "uris": ["/index.html"],
    "plugin_config_id": 1,
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "39.97.63.215:80": 1
        }
    }
    "plugins": {
        "proxy-rewrite": {
            "uri": "/test/add",
            "scheme": "https",
            "host": "apisix.iresty.com"
        },
        "limit-count": {
            "count": 20,
            "time_window": 60,
            "rejected_code": 503,
            "key": "remote_addr"
        }
    }
}
```

等于

```
{
    "uris": ["/index.html"],
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "39.97.63.215:80": 1
        }
    }
    "plugins": {
        "ip-restriction": {
            "whitelist": [
                "127.0.0.0/24",
                "113.74.26.106"
            ]
        },
        "proxy-rewrite": {
            "uri": "/test/add",
            "scheme": "https",
            "host": "apisix.iresty.com"
        },
        "limit-count": {
            "count": 2,
            "time_window": 60,
            "rejected_code": 503
        }
    }
}
```
