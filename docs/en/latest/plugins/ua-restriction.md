---
title: ua-restriction
keywords:
  - APISIX
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

A common scenario is to set crawler rules. `User-Agent` is the identity of the client when sending requests to the server, and the user can whitelist or blacklist some crawler request headers in the `ua-restriction` Plugin.

## Attributes

| Name           | Type          | Required | Default      | Valid values            | Description                                                                     |
|----------------|---------------|----------|--------------|-------------------------|---------------------------------------------------------------------------------|
| bypass_missing | boolean       | False    | false        |                         | When set to `true`, bypasses the check when the `User-Agent` header is missing. |
| allowlist      | array[string] | False    |              |                         | List of allowed `User-Agent` headers.                                           |
| denylist       | array[string] | False    |              |                         | List of denied `User-Agent` headers.                                            |
| message        | string        | False    | "Not allowed" | [1, 1024] | Message with the reason for denial to be added to the response.                 |

:::note

Both `allowlist` and `denylist` can be used on their own. If they are used together, the `allowlist` matches before the `denylist`.

:::

## Enabling the Plugin

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
        "ua-restriction": {
             "bypass_missing": true,
             "allowlist": [
                 "my-bot1",
                 "(Baiduspider)/(\\d+)\\.(\\d+)"
             ],
             "denylist": [
                 "my-bot2",
                 "(Twitterspider)/(\\d+)\\.(\\d+)"
             ]
        }
    }
}'
```

You can also configure the Plugin to respond with a custom rejection message:

```json
"plugins": {
    "ua-restriction": {
        "denylist": [
            "my-bot2",
            "(Twitterspider)/(\\d+)\\.(\\d+)"
        ],
        "message": "Do you want to do something bad?"
    }
}
```

## Example usage

After you have configured the Plugin as shown above, you can make a normal request which will get accepted:

```shell
curl http://127.0.0.1:9080/index.html -i
```

```shell
HTTP/1.1 200 OK
...
```

Now if the `User-Agent` header is in the `denylist` i.e the bot User-Agent:

```shell
curl http://127.0.0.1:9080/index.html --header 'User-Agent: Twitterspider/2.0'
```

```shell
HTTP/1.1 403 Forbidden
...
{"message":"Not allowed"}
```

## Disable Plugin

To disable the `ua-restriction` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

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
