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

To reuse common plugin configurations, you can extract them into a plugin config and
bind it with a route directly.

For instance, you can do something like:

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
            "39.97.63.215:80": 1
        }
    }
}'
```

When we can't find the corresponding plugin config with the id, the requests hit the route will be terminated with HTTP status code 503.

When a route already have `plugins` field configured, the `plugins` in the plugin config
will be merged into it. The same plugin in the plugin config will override one in the `plugins`.

For example, when we configure a plugin config

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

to

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

is equal to

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
