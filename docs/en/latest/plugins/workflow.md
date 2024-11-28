---
title: workflow
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - workflow
  - traffic control
description: This document describes the Apache APISIX workflow Plugin, you can use it to control traffic.
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

The `workflow` plugin is used to introduce [lua-resty-expr](https://github.com/api7/lua-resty-expr#operator-list) to provide complex traffic control features.

## Attributes

| Name                         | Type          | Required | Default | Valid values | Description                                                  |
| ---------------------------- | ------------- | -------- | ------- | ------------ | ------------------------------------------------------------ |
| rules.case                   | array[array]  | False     |         |              | List of variables to match for filtering requests for conditional traffic split. It is in the format `{variable operator value}`. For example, `{"arg_name", "==", "json"}`. The variables here are consistent with NGINX internal variables. For details on supported operators, you can refer to [lua-resty-expr](https://github.com/api7/lua-resty-expr#operator-list). |
| rules.actions                | array[object] | True     |         |              | The action to be performed when the case matches successfully. Currently, only one element is supported in actions. The first child element of the actions' only element can be `return` or `limit-count`. |

### `actions` Attributes

#### return

| Name                   | Type          | Required | Default | Valid values | Description                                                  |
| ---------------------- | ------------- | -------- | ------- | ------------ | ----------------------------------------------------------   |
| actions[1].return      | string        | False    |         |              | Return directly to the client.                               |
| actions[1].[2].code    | integer       | False    |         |              | HTTP status code returned to the client.                     |

#### limit-count

| Name                   | Type          | Required | Default | Valid values | Description                                                      |
| ---------------------- | ------------- | -------- | ------- | ------------ | ---------------------------------------------------------------- |
| actions[1].limit-count | string        | False    |         |              | Execute the functions of the `limit-count` plugin.               |
| actions[1].[2]         | object        | False    |         |              | Configuration of `limit-count` plugin, `group` is not supported. |

:::note

In `rules`, match `case` in order according to the index of the `rules`, and execute `actions` directly if `case` match.
If `case` is missing, the default behavior is to match.

:::

## Enable Plugin

You can configure the `workflow` plugin on a Route as shown below:

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri":"/hello/*",
    "plugins":{
        "workflow":{
            "rules":[
                {
                    "case":[
                        ["uri", "==", "/hello/rejected"]
                    ],
                    "actions":[
                        [
                            "return",
                            {"code": 403}
                        ]
                    ]
                },
                {
                    "case":[
                        ["uri", "==", "/hello/v2/appid"]
                    ],
                    "actions":[
                        [
                            "limit-count",
                            {
                                "count":2,
                                "time_window":60,
                                "rejected_code":429
                            }
                        ]
                    ]
                }
            ]
        }
    },
    "upstream":{
        "type":"roundrobin",
        "nodes":{
            "127.0.0.1:1980":1
        }
    }
}'
```

Here, the `workflow` Plugin is enabled on the Route. If the request matches the `case` in the `rules`, the `actions` will be executed.

**Example 1: If the requested uri is `/hello/rejected`, the status code `403` is returned to the client**

```shell
curl http://127.0.0.1:9080/hello/rejected -i
HTTP/1.1 403 Forbidden
......

{"error_msg":"rejected by workflow"}
```

**Example 2: if the request uri is `/hello/v2/appid`, the `workflow` plugin would execute the `limit-count` plugin**

```shell
curl http://127.0.0.1:9080/hello/v2/appid -i
HTTP/1.1 200 OK
```

```shell
curl http://127.0.0.1:9080/hello/v2/appid -i
HTTP/1.1 200 OK
```

```shell
curl http://127.0.0.1:9080/hello/v2/appid -i
HTTP/1.1 429 Too Many Requests
```

**Example 3: if the request can not match any `case` in the `rules`, the `workflow` plugin would do nothing**

```shell
curl http://127.0.0.1:9080/hello/fake -i
HTTP/1.1 200 OK
```

## Delete Plugin

To remove the `workflow` plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri":"/hello/*",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```
