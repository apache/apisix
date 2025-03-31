---
title: ip-restriction
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - IP restriction
  - ip-restriction
description: The ip-restriction Plugin supports restricting access to upstream resources by IP addresses, through either configuring a whitelist or blacklist of IP addresses.
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

<head>
  <link rel="canonical" href="https://docs.api7.ai/hub/ip-restriction" />
</head>

## Description

The `ip-restriction` Plugin supports restricting access to upstream resources by IP addresses, through either configuring a whitelist or blacklist of IP addresses. Restricting IP to resources helps prevent unauthorized access and harden API security.

## Attributes

| Name          | Type          | Required | Default                          | Valid values | Description                                                            |
|---------------|---------------|----------|----------------------------------|--------------|------------------------------------------------------------------------|
| whitelist     | array[string] | False    |                                  |              | List of IPs or CIDR ranges to whitelist.                               |
| blacklist     | array[string] | False    |                                  |              | List of IPs or CIDR ranges to blacklist.                               |
| message       | string        | False    | "Your IP address is not allowed" | [1, 1024]    | Message returned when the IP address is not allowed access.            |
| response_code | integer       | False    | 403                              | [403, 404]   | HTTP response code returned when the IP address is not allowed access. |

:::note

At least one of the `whitelist` or `blacklist` should be configured, but they cannot be configured at the same time.

:::

## Examples

The examples below demonstrate how you can configure the `ip-restriction` Plugin for different scenarios.

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Restrict Access by Whitelisting

The following example demonstrates how you can whitelist a list of IP addresses that should have access to the upstream resource and customize the error message for access denial.

Create a Route with the `ip-restriction` Plugin to whitelist a range of IPs and customize the error message when the access is denied:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "ip-restriction-route",
    "uri": "/anything",
    "plugins": {
      "ip-restriction": {
        "whitelist": [
          "192.168.0.1/24"
        ],
        "message": "Access denied"
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```

Send a request to the Route:

```shell
curl -i "http://127.0.0.1:9080/anything"
```

If your IP is allowed, you should receive an `HTTP/1.1 200 OK` response. If not, you should receive an `HTTP/1.1 403 Forbidden` response with the following error message:

```text
{"message":"Access denied"}
```

### Restrict Access Using Modified IP

The following example demonstrates how you can modify the IP used for IP restriction, using the `real-ip` Plugin. This is particularly useful if APISIX is behind a reverse proxy and the real client IP is not available to APISIX.

Create a Route with the `ip-restriction` Plugin to whitelist a specific IP address and obtain client IP address from the URL parameter `realip`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "ip-restriction-route",
    "uri": "/anything",
    "plugins": {
      "ip-restriction": {
        "whitelist": [
          "192.168.1.241"
        ]
      },
      "real-ip": {
        "source": "arg_realip"
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
      "httpbin.org:80": 1
      }
    }
  }'
```

Send a request to the Route:

```shell
curl -i "http://127.0.0.1:9080/anything?realip=192.168.1.241"
```

You should receive an `HTTP/1.1 200 OK` response.

Send another request with a different IP address:

```shell
curl -i "http://127.0.0.1:9080/anything?realip=192.168.10.24"
```

You should receive an `HTTP/1.1 403 Forbidden` response.
