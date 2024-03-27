---
title: ua-restriction
keywords:
  - Apache APISIX
  - API Gateway
  - UA restriction
description: This document contains information about the Apache APISIX ua-restriction Plugin, which allows you to restrict access to a Route or Service based on the User-Agent header with an allowlist and a denylist.
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

The `ua-restriction` Plugin allows you to restrict access to a Route or Service based on the `User-Agent` header with an `allowlist` and a `denylist`.

A common scenario is to set crawler rules. `User-Agent` is the identity of the client when sending requests to the server, and the user can allow or deny some crawler request headers in the `ua-restriction` Plugin.

## Attributes

| Name           | Type          | Required | Default      | Valid values            | Description                                                                     |
|----------------|---------------|----------|--------------|-------------------------|---------------------------------------------------------------------------------|
| bypass_missing | boolean       | False    | false        |                         | When set to `true`, bypasses the check when the `User-Agent` header is missing. |
| allowlist      | array[string] | False    |              |                         | List of allowed `User-Agent` headers.                                           |
| denylist       | array[string] | False    |              |                         | List of denied `User-Agent` headers.                                            |
| message        | string        | False    | "Not allowed" |  | Message with the reason for denial to be added to the response.                 |

:::note

`allowlist` and `denylist` can't be configured at the same time.

:::

## Enable Plugin

You can enable the Plugin on a Route or a Service as shown below:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/index.html",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    },
    "plugins": {
        "ua-restriction": {
             "bypass_missing": true,
             "denylist": [
                 "my-bot2",
                 "(Twitterspider)/(\\d+)\\.(\\d+)"
             ],
             "message": "Do you want to do something bad?"
        }
    }
}'
```

## Example usage

Send a request to the route:

```shell
curl http://127.0.0.1:9080/index.html -i
```

You should receive an `HTTP/1.1 200 OK` response.

Now if the `User-Agent` header is in the `denylist` i.e the bot User-Agent:

```shell
curl http://127.0.0.1:9080/index.html --header 'User-Agent: Twitterspider/2.0'
```

You should receive an `HTTP/1.1 403 Forbidden` response with the following message:

```text
{"message":"Do you want to do something bad?"}
```

## Delete Plugin

To remove the `ua-restriction` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
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
