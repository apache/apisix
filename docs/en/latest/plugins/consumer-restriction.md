---
title: consumer-restriction
keywords:
  - Apache APISIX
  - API Gateway
  - Consumer restriction
description: The Consumer Restriction Plugin allows users to configure access restrictions on Consumer, Route, Service, or Consumer Group.
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

The `consumer-restriction` Plugin allows users to configure access restrictions on Consumer, Route, Service, or Consumer Group.

## Attributes

| Name                       | Type          | Required | Default       | Valid values                                                 | Description                                                  |
| -------------------------- | ------------- | -------- | ------------- | ------------------------------------------------------------ | ------------------------------------------------------------ |
| type                       | string        | False    | consumer_name | ["consumer_name", "consumer_group_id", "service_id", "route_id"] | Type of object to base the restriction on.                   |
| whitelist                  | array[string] | True     |               |                                                              | List of objects to whitelist. Has a higher priority than `allowed_by_methods`. |
| blacklist                  | array[string] | True     |               |                                                              | List of objects to blacklist. Has a higher priority than `whitelist`. |
| rejected_code              | integer       | False    | 403           | [200,...]                                                    | HTTP status code returned when the request is rejected.      |
| rejected_msg               | string        | False    |               |                                                              | Message returned when the request is rejected.               |
| allowed_by_methods         | array[object] | False    |               |                                                              | List of allowed configurations for Consumer settings, including a username of the Consumer and a list of allowed HTTP methods. |
| allowed_by_methods.user    | string        | False    |               |                                                              | A username for a Consumer.                                   |
| allowed_by_methods.methods | array[string] | False    |               | ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS", "CONNECT", "TRACE", "PURGE"] | List of allowed HTTP methods for a Consumer.                 |

:::note

The different values in the `type` attribute have these meanings:

- `consumer_name`: Username of the Consumer to restrict access to a Route or a Service.
- `consumer_group_id`: ID of the Consumer Group to restrict access to a Route or a Service.
- `service_id`: ID of the Service to restrict access from a Consumer. Need to be used with an Authentication Plugin.
- `route_id`: ID of the Route to restrict access from a Consumer.

:::

## Example usage

### Restricting by `consumer_name`

The example below shows how you can use the `consumer-restriction` Plugin on a Route to restrict specific consumers.

You can first create two consumers `jack1` and `jack2`:

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/consumers -H "X-API-KEY: $admin_key" -X PUT -i -d '
{
    "username": "jack1",
    "plugins": {
        "basic-auth": {
            "username":"jack2019",
            "password": "123456"
        }
    }
}'

curl http://127.0.0.1:9180/apisix/admin/consumers -H "X-API-KEY: $admin_key" -X PUT -i -d '
{
    "username": "jack2",
    "plugins": {
        "basic-auth": {
            "username":"jack2020",
            "password": "123456"
        }
    }
}'
```

Next, you can configure the Plugin to the Route:

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
        "basic-auth": {},
        "consumer-restriction": {
            "whitelist": [
                "jack1"
            ]
        }
    }
}'
```

Now, this configuration will only allow `jack1` to access your Route:

```shell
curl -u jack2019:123456 http://127.0.0.1:9080/index.html
```

```shell
HTTP/1.1 200 OK
```

And requests from `jack2` are blocked:

```shell
curl -u jack2020:123456 http://127.0.0.1:9080/index.html -i
```

```shell
HTTP/1.1 403 Forbidden
...
{"message":"The consumer_name is forbidden."}
```

### Restricting by `allowed_by_methods`

The example below configures the Plugin to a Route to restrict `jack1` to only make `POST` requests:

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
        "basic-auth": {},
        "consumer-restriction": {
            "allowed_by_methods":[{
                "user": "jack1",
                "methods": ["POST"]
            }]
        }
    }
}'
```

Now if `jack1` makes a `GET` request, the access is restricted:

```shell
curl -u jack2019:123456 http://127.0.0.1:9080/index.html
```

```shell
HTTP/1.1 403 Forbidden
...
{"message":"The consumer_name is forbidden."}
```

To also allow `GET` requests, you can update the Plugin configuration and it would be reloaded automatically:

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
        "basic-auth": {},
        "consumer-restriction": {
            "allowed_by_methods":[{
                "user": "jack1",
                "methods": ["POST","GET"]
            }]
        }
    }
}'
```

Now, if a `GET` request is made:

```shell
curl -u jack2019:123456 http://127.0.0.1:9080/index.html
```

```shell
HTTP/1.1 200 OK
```

### Restricting by `service_id`

To restrict a Consumer from accessing a Service, you also need to use an Authentication Plugin. The example below uses the [key-auth](./key-auth.md) Plugin.

First, you can create two services:

```shell
curl http://127.0.0.1:9180/apisix/admin/services/1 -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "upstream": {
        "nodes": {
            "127.0.0.1:1980": 1
        },
        "type": "roundrobin"
    },
    "desc": "new service 001"
}'

curl http://127.0.0.1:9180/apisix/admin/services/2 -H "X-API-KEY: $admin_key" -X PUT -d '
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

Then configure the `consumer-restriction` Plugin on the Consumer with the `key-auth` Plugin and the `service_id` to whitelist.

```shell
curl http://127.0.0.1:9180/apisix/admin/consumers -H "X-API-KEY: $admin_key" -X PUT -d '
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

Finally, you can configure the `key-auth` Plugin and bind the service to the Route:

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
    "service_id": 1,
    "plugins": {
         "key-auth": {
        }
    }
}'
```

Now, if you test the Route, you should be able to access the Service:

```shell
curl http://127.0.0.1:9080/index.html -H 'apikey: auth-jack' -i
```

```shell
HTTP/1.1 200 OK
...
```

Now, if the Route is configured to the Service with `service_id` `2`:

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
    "service_id": 2,
    "plugins": {
         "key-auth": {
        }
    }
}'
```

Since the Service is not in the whitelist, it cannot be accessed:

```shell
curl http://127.0.0.1:9080/index.html -H 'apikey: auth-jack' -i
```

```shell
HTTP/1.1 403 Forbidden
...
{"message":"The service_id is forbidden."}
```

## Delete Plugin

To remove the `consumer-restriction` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

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
        "basic-auth": {}
    }
}'
```
