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

- [中文](../zh-cn/plugins/consumer-restriction.md)

# Summary
  - [Introduction](#introduction)
  - [Attributes](#attributes)
  - [Example](#example)
    - [How to restrict consumer_name](#how-to-restrict-consumer_name)
    - [How to restrict service_id](#how-to-restrict-service_id)
  - [Disable Plugin](#disable-plugin)


## Introduction

The `consumer-restriction` makes corresponding access restrictions based on different objects selected.

## Attributes

|Name       |   Type      | Requirement  | Default       | Valid                           | Description                                                                                                                         |
|-----------|-------------|--------------|---------------|---------------------------------|--------------------------------------------------------------------------------------------------------------------                 |
| type      | string      | optional     | consumer_name | ["consumer_name", "service_id"] | According to different objects, corresponding restrictions, support `consumer_name`, `service_id`.                 |
| whitelist | array[string] | required   |               |                                 | Choose one of the two with `blacklist`, only whitelist or blacklist can be enabled separately, and the two cannot be used together. |
| blacklist | array[string] | required   |               |                                 | Choose one of the two with `whitelist`, only whitelist or blacklist can be enabled separately, and the two cannot be used together. |
| rejected_code | integer | optional     | 403           | [200,...]                       | The HTTP status code returned when the request is rejected.                                                                         |

For the `type` field is an enumerated type, it can be `consumer_name` or `service_id`. They stand for the following meanings:
* **consumer_name**: Add the `username` of `consumer` to a whitelist or blacklist (supporting single or multiple consumers) to restrict access to services or routes.
* **service_id**: Add the `id` of the `service` to a whitelist or blacklist (supporting one or more services) to restrict access to the service. It needs to be used in conjunction with authorized plugins.

## Example

### How to restrict `consumer_name`

The following is an example. The `consumer-restriction` plugin is enabled on the specified route to restrict consumer access.

```shell
curl http://127.0.0.1:9080/apisix/admin/consumers -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -i -d '
{
    "username": "jack1",
    "plugins": {
        "basic-auth": {
            "username":"jack2019",
            "password": "123456"
        }
    }
}'

curl http://127.0.0.1:9080/apisix/admin/consumers -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -i -d '
{
    "username": "jack2",
    "plugins": {
        "basic-auth": {
            "username":"jack2020",
            "password": "123456"
        }
    }
}'

curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/index.html",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    },
    "plugins": {
        "basic-auth": {},
        "consumer-restriction": {
            "whitelist": [
                "jack1"
            ]
        }
    }
}'
```

**Test Plugin**

Requests from jack1:

```shell
curl -u jack2019:123456 http://127.0.0.1:9080/index.html
HTTP/1.1 200 OK
...
```

Requests from jack2:

```shell
curl -u jack2020:123456 http://127.0.0.1:9080/index.html -i
HTTP/1.1 403 Forbidden
...
{"message":"The consumer_name is forbidden."}
```

## How to restrict `service_id`

The `service_id` method needs to be used together with the authorization plug-in. Here, the key-auth authorization plug-in is taken as an example.

1. Create two services.

```shell
curl http://127.0.0.1:9080/apisix/admin/services/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "upstream": {
        "nodes": {
            "127.0.0.1:1980": 1
        },
        "type": "roundrobin"
    },
    "desc": "new service 001"
}'

curl http://127.0.0.1:9080/apisix/admin/services/2 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "upstream": {
        "nodes": {
            "127.0.0.1:1980": 1
        },
        "type": "roundrobin"
    },
    "desc": "new service 002"
}'
```

2. Bind the `consumer-restriction` plugin on the `consumer` (need to cooperate with an authorized plugin to bind), and add the `service_id` whitelist list.

```shell
curl http://127.0.0.1:9080/apisix/admin/consumers -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "username": "new_consumer",
    "plugins": {
    "key-auth": {
        "key": "auth-jack"
    },
    "consumer-restriction": {
           "type": "service_id",
            "whitelist": [
                "1"
            ],
            "rejected_code": 403
        }
    }
}'
```

3. Open the `key-auth` plugin on the route and bind the `service_id` to `1`.

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/index.html",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    },
    "service_id": 1,
    "plugins": {
         "key-auth": {
        }
    }
}'
```

**Test Plugin**

```shell
curl http://127.0.0.1:9080/index.html -H 'apikey: auth-jack' -i
HTTP/1.1 200 OK
...
```

The `service_id` in the whitelist column allows access, and the plug-in configuration takes effect.

4. Open the `key-auth` plugin on the route and bind the `service_id` to `2`.

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/index.html",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    },
    "service_id": 2,
    "plugins": {
         "key-auth": {
        }
    }
}'
```

**Test Plugin**

```shell
curl http://127.0.0.1:9080/index.html -H 'apikey: auth-jack' -i
HTTP/1.1 403 Forbidden
...
{"message":"The service_id is forbidden."}
```

It means that the `service_id` that is not in the whitelist is denied access, and the plug-in configuration takes effect.

## Disable Plugin

When you want to disable the `consumer-restriction` plugin, it is very simple,
you can delete the corresponding json configuration in the plugin configuration,
no need to restart the service, it will take effect immediately:

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/index.html",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    },
    "plugins": {
        "basic-auth": {}
    }
}'
```

The `consumer-restriction` plugin has been disabled now. It works for other plugins.
