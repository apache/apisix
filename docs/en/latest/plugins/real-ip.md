---
title: real-ip
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - Real IP
description: This document contains information about the Apache APISIX real-ip Plugin.
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

## Description

The `real-ip` Plugin is used to dynamically change the client's IP address and port as seen by APISIX.

This is more flexible but functions similarly to Nginx's [ngx_http_realip_module](https://nginx.org/en/docs/http/ngx_http_realip_module.html).

:::info IMPORTANT

This Plugin requires APISIX to run on [APISIX-Runtime](../FAQ.md#how-do-i-build-the-apisix-runtime-environment).

:::

## Attributes

| Name              | Type          | Required | Valid values                                                    | Description                                                                                                                                                                                                                                                                                                                                                |
|-------------------|---------------|----------|-----------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| source            | string        | True     | Any Nginx variable like `arg_realip` or `http_x_forwarded_for`. | Dynamically sets the client's IP address and an optional port, or the client's host name, from APISIX's view.                                                                                                                                                                                                                                                                          |
| trusted_addresses | array[string] | False    | List of IPs or CIDR ranges.                                     | Dynamically sets the `set_real_ip_from` field.                                                                                                                                                                                                                                                                                                             |
| recursive         | boolean       | False    | True to enable, false to disable, default is false              | If recursive search is disabled, the original client address that matches one of the trusted addresses is replaced by the last address sent in the configured `source`. If recursive search is enabled, the original client address that matches one of the trusted addresses is replaced by the last non-trusted address sent in the configured `source`. |

:::note

If the address specified in `source` is missing or invalid, the Plugin would not change the client address.

:::

## Enable Plugin

The example below enables the `real-ip` Plugin on the specified Route:

```shell
curl -i http://127.0.0.1:9180/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

## Example usage

After you have enabled the Plugin as mentioned above, you can test it as shown below:

```shell
curl 'http://127.0.0.1:9080/index.html?realip=1.2.3.4:9080' -I
```

```shell
...
remote-addr: 1.2.3.4
remote-port: 9080
```

## Delete Plugin

To remove the `real-ip` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
