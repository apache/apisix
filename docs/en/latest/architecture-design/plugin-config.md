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

Plugin Configs are used to extract commonly used [Plugin](./plugin.md) configurations and can be bound directly to a [Route](./route.md).

The example below illustrates how this can be used:

```shell
# create a plugin config
$ curl http://127.0.0.1:9080/apisix/admin/plugin_configs/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -i -d '
{
    "desc": "blah",
    "plugins": {
        "limit-count": {
            "count": 2,
            "time_window": 60,
            "rejected_code": 503
        }
    }
}'

# bind it to route
$ curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -i -d '
{
    "uris": ["/index.html"],
    "plugin_config_id": 1,
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```

When APISIX can't find the Plugin Config with the `id`, the requests reaching this Route are terminated with a status code of 503.

If a Route already has the `plugins` field configured, the plugins in the Plugin Config will effectively be merged to it. The same plugin in the Plugin Config will override the ones configured directly in the Route.

For example, if we configure a Plugin Config as shown below

```
{
    "desc": "I am plugin_config 1",
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

to a Route as shown below,

```
{
    "uris": ["/index.html"],
    "plugin_config_id": 1,
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
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

the effective configuration will be as the one shown below:

```
{
    "uris": ["/index.html"],
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
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
