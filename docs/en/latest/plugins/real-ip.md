---
title: real-ip
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

## Summary

- [**Name**](#name)
- [**Attributes**](#attributes)
- [**How To Enable**](#how-to-enable)
- [**Test Plugin**](#test-plugin)
- [**Disable Plugin**](#disable-plugin)

## Name

The `real-ip` plugin dynamically changes the client's IP and port seen by APISIX.

It works like Nginx's `ngx_http_realip_module`, but is more flexible.

**This plugin requires APISIX to run on [APISIX-OpenResty](../how-to-build.md#step-6-build-openresty-for-apache-apisix).**

## Attributes

| Name      | Type          | Requirement | Default    | Valid                                                                    | Description                                                                                                                                         |
| --------- | ------------- | ----------- | ---------- | ------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| source      | string        | required    |            | Any Nginx variable like `arg_realip` or `http_x_forwarded_for`| dynamically set the client's IP and port in APISIX's view, according to the value of variable. If the value doesn't contain a port, the client's port won't be changed. |
| trusted_addresses| array[string] | optional    |            | List of IPs or CIDR ranges | dynamically set the `set_real_ip_from` directive |

If the remote address comes from `source` is missing or invalid, this plugin will just let it go and don't change the client address.

## How To Enable

Here's an example, enable this plugin on the specified route:

```shell
curl -i http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/index.html",
    "plugins": {
        "real-ip": {
            "source": "arg_realip",
            "trusted_addresses": ["127.0.0.0/24"]
        },
        "response-rewrite": {
            "headers": {
                "remote_addr": "$remote_addr",
                "remote_port": "$remote_port"
            }
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```

## Test Plugin

Use curl to access:

```shell
curl 'http://127.0.0.1:9080/index.html?realip=1.2.3.4:9080' -I
...
remote-addr: 1.2.3.4
remote-port: 9080
```

## Disable Plugin

When you want to disable this plugin, it is very simple,
you can delete the corresponding JSON configuration in the plugin configuration,
no need to restart the service, it will take effect immediately:

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/index.html",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```

This plugin has been disabled now. It works for other plugins.
