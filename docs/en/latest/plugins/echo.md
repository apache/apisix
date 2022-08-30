---
title: echo
keywords:
  - APISIX
  - Plugin
  - Echo
description: This document contains information about the Apache APISIX echo Plugin.
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

The `echo` Plugin is to help users understand how they can develop an APISIX Plugin.

This Plugin addresses common functionalities in phases like init, rewrite, access, balancer, header filter, body filter and log.

:::caution WARNING

The `echo` Plugin is built as an example. It has missing cases and should **not** be used in production environments.

:::

## Attributes

| Name        | Type   | Requirement | Default | Valid | Description                               |
| ----------- | ------ | ----------- | ------- | ----- | ----------------------------------------- |
| before_body | string | optional    |         |       | Body to use before the filter phase.      |
| body        | string | optional    |         |       | Body that replaces the Upstream response. |
| after_body  | string | optional    |         |       | Body to use after the modification phase. |
| headers     | object | optional    |         |       | New headers to use for the response.      |

At least one of `before_body`, `body`, and `after_body` must be specified.

## Enabling the Plugin

The example below shows how you can enable the `echo` Plugin for a specific Route:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "plugins": {
        "echo": {
            "before_body": "before the body modification "
        }
    },
    "upstream": {
        "nodes": {
            "127.0.0.1:1980": 1
        },
        "type": "roundrobin"
    },
    "uri": "/hello"
}'
```

## Example usage

First, we configure the Plugin as mentioned above. We can then make a request as shown below:

```shell
curl -i http://127.0.0.1:9080/hello
```

```
HTTP/1.1 200 OK
...
before the body modification hello world
```

## Disable Plugin

To disable the `echo` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/hello",
    "plugins": {},
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```
