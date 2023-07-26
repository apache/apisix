---
title: ip-restriction
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - IP restriction
  - ip-restriction
description: This document contains information about the Apache APISIX ip-restriction Plugin.
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

The `ip-restriction` Plugin allows you to restrict access to a Service or a Route by either whitelisting or blacklisting IP addresses.

Single IPs, multiple IPs or even IP ranges in CIDR notation like `10.10.10.0/24` can be used.

## Attributes

| Name      | Type          | Required | Default                         | Valid values | Description                                                 |
|-----------|---------------|----------|---------------------------------|--------------|-------------------------------------------------------------|
| whitelist | array[string] | False    |                                 |              | List of IPs or CIDR ranges to whitelist.                    |
| blacklist | array[string] | False    |                                 |              | List of IPs or CIDR ranges to blacklist.                    |
| message   | string        | False    | "Your IP address is not allowed" | [1, 1024]    | Message returned when the IP address is not allowed access. |

:::note

Either one of `whitelist` or `blacklist` attribute must be specified. They cannot be used together.

:::

## Enable Plugin

You can enable the Plugin on a Route or a Service as shown below:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/index.html",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    },
    "plugins": {
        "ip-restriction": {
            "whitelist": [
                "127.0.0.1",
                "113.74.26.106/24"
            ]
        }
    }
}'
```

To return a custom message when an IP address is not allowed access, configure it in the Plugin as shown below:

```json
"plugins": {
    "ip-restriction": {
        "whitelist": [
            "127.0.0.1",
            "113.74.26.106/24"
        ],
        "message": "Do you want to do something bad?"
    }
}
```

## Example usage

After you have configured the Plugin as shown above, when you make a request from the IP `127.0.0.1`:

```shell
curl http://127.0.0.1:9080/index.html -i
```

```shell
HTTP/1.1 200 OK
...
```

But if you make requests from `127.0.0.2`:

```shell
curl http://127.0.0.1:9080/index.html -i --interface 127.0.0.2
```

```
HTTP/1.1 403 Forbidden
...
{"message":"Your IP address is not allowed"}
```

To change the whitelisted/blacklisted IPs, you can update the Plugin configuration. The changes are hot reloaded and there is no need to restart the service.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/index.html",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    },
    "plugins": {
        "ip-restriction": {
            "whitelist": [
                "127.0.0.2",
                "113.74.26.106/24"
            ]
        }
    }
}'
```

## Delete Plugin

To remove the `ip-restriction` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/index.html",
    "plugins": {},
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```
