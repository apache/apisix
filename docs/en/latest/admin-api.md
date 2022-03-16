---
title: Admin API
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

The Admin API lets users control their deployed Apache APISIX instance. The [architecture design](./architecture-design/apisix.md) gives an idea about how everything fits together.

By default, the Admin API listens to port `9080` (`9443` for HTTPS) when APISIX is launched. This can be changed by modifying your configuration file ([conf/config.yaml](https://github.com/apache/apisix/blob/master/conf/config.yaml)).

**Note**: Mentions of `X-API-KEY` in this document refers to `apisix.admin_key.key`—the access token for Admin API—in your configuration file.

## Route

**API**: /apisix/admin/routes/{id}?ttl=0

[Routes](./architecture-design/route.md) match the client's request based on defined rules, loads and executes the corresponding [plugins](#plugin), and forwards the request to the specified [Upstream](#upstream).

**Note**: When the Admin API is enabled, to avoid conflicts with your design API, use a different port for the Admin API. This can be set in your configuration file by changing the `port_admin` key.

### Request Methods

| Method | Request URI                      | Request Body | Description                                                                                                                   |
| ------ | -------------------------------- | ------------ | ----------------------------------------------------------------------------------------------------------------------------- |
| GET    | /apisix/admin/routes             | NULL         | Fetches a list of all configured Routes.                                                                                 |
| GET    | /apisix/admin/routes/{id}        | NULL         | Fetches specified Route by id.                                                                                                |
| PUT    | /apisix/admin/routes/{id}        | {...}        | Creates a Route with the specified id.                                                                                            |
| POST   | /apisix/admin/routes             | {...}        | Creates a Route and assigns a random id.                                                                                            |
| DELETE | /apisix/admin/routes/{id}        | NULL         | Removes the Route with the specified id.                                                                                      |
| PATCH  | /apisix/admin/routes/{id}        | {...}        | Updates the selected attributes of the specified, existing Route. To delete an attribute, set value of attribute set to null. |
| PATCH  | /apisix/admin/routes/{id}/{path} | {...}        | Updates the attribute specified in the path. The values of other attributes remain unchanged.                                 |

### URI Request Parameters

| parameter | Required | Type      | Description                                         | Example |
| --------- | -------- | --------- | --------------------------------------------------- | ------- |
| ttl       | False    | Auxiliary | Request expires after the specified target seconds. | ttl=1   |

### Request Body Parameters

| Parameter        | Required                                 | Type        | Description                                                                                                                                                                                                                                                                                    | Example                                              |
| ---------------- | ---------------------------------------- | ----------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------- |
| name             | False                                    | Auxiliary   | Identifier for the Route.                                                                                                                                                                                                                                                                      | route-xxxx                                           |
| desc             | False                                    | Auxiliary   | Description of usage scenarios.                                                                                                                                                                                                                                                                | route xxxx                                           |
| uri              | True, can't be used with `uris`          | Match Rules | Matches the uri. For more advanced matching see [Router](./architecture-design/router.md).                                                                                                                                                                                                     | "/hello"                                             |
| uris             | True, can't be used with `uri`           | Match Rules | Matches with any one of the multiple `uri`s specified in the form of a non-empty list.                                                                                                                                                                                                         | ["/hello", "/word"]                                  |
| host             | False, can't be used with `hosts`        | Match Rules | Matches with domain names such as `foo.com` or PAN domain names like `*.foo.com`.                                                                                                                                                                                                              | "foo.com"                                            |
| hosts            | False, can't be used with `host`         | Match Rules | Matches with any one of the multiple `host`s specified in the form of a non-empty list.                                                                                                                                                                                                        | ["foo.com", "*.bar.com"]                             |
| remote_addr      | False, can't be used with `remote_addrs` | Match Rules | Matches with the specified IP address in standard IPv4 format (`192.168.1.101`), CIDR format (`192.168.1.0/24`), or in IPv6 format (`::1`, `fe80::1`, `fe80::1/64`).                                                                                                                           | "192.168.1.0/24"                                     |
| remote_addrs     | False, can't be used with `remote_addr`  | Match Rules | Matches with any one of the multiple `remote_addr`s specified in the form of a non-empty list.                                                                                                                                                                                                 | ["127.0.0.1", "192.0.0.0/8", "::1"]                  |
| methods          | False                                    | Match Rules | Matches with the specified methods. Matches all methods if empty or unspecified.                                                                                                                                                                                                               | ["GET", "POST"]                                      |
| priority         | False                                    | Match Rules | If different Routes matches to the same `uri`, then the Route is matched based on its `priority`. A higher value corresponds to higher priority. It is set to `0` by default.                                                                                                                  | priority = 10                                        |
| vars             | False                                    | Match Rules | Matches based on the specified variables consistent with variables in Nginx. Takes the form `[[var, operator, val], [var, operator, val], ...]]`. Note that this is case sensitive when matching a cookie name. See [lua-resty-expr](https://github.com/api7/lua-resty-expr) for more details. | [["arg_name", "==", "json"], ["arg_age", ">", 18]]   |
| filter_func      | False                                    | Match Rules | Matches based on a user-defined filtering function. Used in scenarios requiring complex matching. These functions can accept an input parameter `vars` which can be used to access the Nginx variables.                                                                                        | function(vars) return vars["arg_name"] == "json" end |
| plugins          | False                                    | Plugin      | Plugins that are executed during the request/response cycle. See [Plugin](architecture-design/plugin.md) for more.                                                                                                                                                                             |                                                      |
| script           | False                                    | Script      | Used for writing arbitrary Lua code or directly calling existing plugins to be executed. See [Script](architecture-design/script.md) for more.                                                                                                                                                 |                                                      |
| upstream         | False                                    | Upstream    | Configuration of the [Upstream](./architecture-design/upstream.md).                                                                                                                                                                                                                            |                                                      |
| upstream_id      | False                                    | Upstream    | Id of the [Upstream](architecture-design/upstream.md) service.                                                                                                                                                                                                                                 |                                                      |
| service_id       | False                                    | Service     | Configuration of the bound [Service](architecture-design/service.md).                                                                                                                                                                                                                          |                                                      |
| plugin_config_id | False, can't be used with `script`       | Plugin      | [Plugin config](architecture-design/plugin-config.md) bound to the Route.                                                                                                                                                                                                                      |                                                      |
| labels           | False                                    | Match Rules | Attributes of the Route specified as key-value pairs.                                                                                                                                                                                                                                          | {"version":"v2","build":"16","env":"production"}     |
| timeout          | False                                    | Auxiliary   | Sets the timeout for connecting to, and sending and receiving messages between the Upstream and the Route. This will overwrite the `timeout` value configured in your [Upstream](#upstream).                                                                                                   | {"connect": 3, "send": 3, "read": 3}                 |
| enable_websocket | False                                    | Auxiliary   | Enables a websocket. Set to `false` by default.                                                                                                                                                                                                                                                |                                                      |
| status           | False                                    | Auxiliary   | Enables the current Route. Set to `1` (enabled) by default.                                                                                                                                                                                                                                    | `1` to enable, `0` to disable                        |
| create_time      | False                                    | Auxiliary   | Epoch timestamp (in seconds) of the created time. If missing, this field will be populated automatically.                                                                                                                                                                                         | 1602883670                                           |
| update_time      | False                                    | Auxiliary   | Epoch timestamp (in seconds) of the updated time. If missing, this field will be populated automatically.                                                                                                                                                                                         | 1602883670                                           |

Example configuration:

```shell
{
    "id": "1",                            # id, unnecessary.
    "uris": ["/a","/b"],                  # A set of uri.
    "methods": ["GET","POST"],            # Can fill multiple methods
    "hosts": ["a.com","b.com"],           # A set of host.
    "plugins": {},                        # Bound plugin
    "priority": 0,                        # If different routes contain the same `uri`, determine which route is matched first based on the attribute` priority`, the default value is 0.
    "name": "route-xxx",
    "desc": "hello world",
    "remote_addrs": ["127.0.0.1"],        # A set of Client IP.
    "vars": [["http_user", "==", "ios"]], # A list of one or more `[var, operator, val]` elements
    "upstream_id": "1",                   # upstream id, recommended
    "upstream": {},                       # upstream, not recommended
    "timeout": {                          # Set the upstream timeout for connecting, sending and receiving messages of the route.
        "connect": 3,
        "send": 3,
        "read": 3
    },
    "filter_func": "",                    # User-defined filtering function
}
```

Example API usage:

```shell
# Create a route
$ curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -i -d '
{
    "uri": "/index.html",
    "hosts": ["foo.com", "*.bar.com"],
    "remote_addrs": ["127.0.0.0/8"],
    "methods": ["PUT", "GET"],
    "enable_websocket": true,
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'

HTTP/1.1 201 Created
Date: Sat, 31 Aug 2019 01:17:15 GMT
...

# Create a route expires after 60 seconds, then it's deleted automatically
$ curl http://127.0.0.1:9080/apisix/admin/routes/2?ttl=60 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -i -d '
{
    "uri": "/aa/index.html",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'

HTTP/1.1 201 Created
Date: Sat, 31 Aug 2019 01:17:15 GMT
...


# Add an upstream node to the Route
$ curl http://127.0.0.1:9080/apisix/admin/routes/1 -H'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PATCH -i -d '
{
    "upstream": {
        "nodes": {
            "127.0.0.1:1981": 1
        }
    }
}'
HTTP/1.1 200 OK
...

After successful execution, upstream nodes will be updated to:
{
    "127.0.0.1:1980": 1,
    "127.0.0.1:1981": 1
}


# Update the weight of an upstream node to the Route
$ curl http://127.0.0.1:9080/apisix/admin/routes/1 -H'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PATCH -i -d '
{
    "upstream": {
        "nodes": {
            "127.0.0.1:1981": 10
        }
    }
}'
HTTP/1.1 200 OK
...

After successful execution, upstream nodes will be updated to:
{
    "127.0.0.1:1980": 1,
    "127.0.0.1:1981": 10
}


# Delete an upstream node for the Route
$ curl http://127.0.0.1:9080/apisix/admin/routes/1 -H'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PATCH -i -d '
{
    "upstream": {
        "nodes": {
            "127.0.0.1:1980": null
        }
    }
}'
HTTP/1.1 200 OK
...

After successful execution, upstream nodes will be updated to:
{
    "127.0.0.1:1981": 10
}


# Replace methods of the Route  --  array
$ curl http://127.0.0.1:9080/apisix/admin/routes/1 -H'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PATCH -i -d '{
    "methods": ["GET", "POST"]
}'
HTTP/1.1 200 OK
...

After successful execution, methods will not retain the original data, and the entire update is:
["GET", "POST"]


# Replace upstream nodes of the Route -- sub path
$ curl http://127.0.0.1:9080/apisix/admin/routes/1/upstream/nodes -H'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PATCH -i -d '
{
    "127.0.0.1:1982": 1
}'
HTTP/1.1 200 OK
...

After successful execution, nodes will not retain the original data, and the entire update is:
{
    "127.0.0.1:1982": 1
}


# Replace methods of the Route -- sub path
$ curl http://127.0.0.1:9080/apisix/admin/routes/1/methods -H'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PATCH -i -d'["POST", "DELETE", " PATCH"]'
HTTP/1.1 200 OK
...

After successful execution, methods will not retain the original data, and the entire update is:
["POST", "DELETE", "PATCH"]


# disable route
$ curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PATCH -i -d '
{
    "status": 0
}'
HTTP/1.1 200 OK
...

After successful execution, status nodes will be updated to:
{
    "status": 0
}


# enable route
$ curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PATCH -i -d '
{
    "status": 1
}'
HTTP/1.1 200 OK
...

After successful execution, status nodes will be updated to:
{
    "status": 1
}


```

### Response Parameters

Currently, the response is returned from etcd.

[Back to TOC](#table-of-contents)

## Service

**API**: /apisix/admin/services/{id}

A Service is an abstraction of an API (which can also be understood as a set of Route abstractions). It usually corresponds to an upstream service abstraction.

The relationship between Routes and a Service is usually N:1.

### Request Methods

| Method | Request URI                        | Request Body | Description                                                                                                                     |
| ------ | ---------------------------------- | ------------ | ------------------------------------------------------------------------------------------------------------------------------- |
| GET    | /apisix/admin/services             | NULL         | Fetches a list of available Services.                                                                                           |
| GET    | /apisix/admin/services/{id}        | NULL         | Fetches specified Service by id.                                                                                                |
| PUT    | /apisix/admin/services/{id}        | {...}        | Creates a Service with the specified id.                                                                                            |
| POST   | /apisix/admin/services             | {...}        | Creates a Service and assigns a random id.                                                                                            |
| DELETE | /apisix/admin/services/{id}        | NULL         | Removes the Service with the specified id.                                                                                      |
| PATCH  | /apisix/admin/services/{id}        | {...}        | Updates the selected attributes of the specified, existing Service. To delete an attribute, set value of attribute set to null. |
| PATCH  | /apisix/admin/services/{id}/{path} | {...}        | Updates the attribute specified in the path. The values of other attributes remain unchanged.                                   |

### Request Body Parameters

| Parameter        | Required | Type        | Description                                                                                                        | Example                                          |
| ---------------- | -------- | ----------- | ------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------ |
| plugins          | False    | Plugin      | Plugins that are executed during the request/response cycle. See [Plugin](architecture-design/plugin.md) for more. |                                                  |
| upstream         | False    | Upstream    | Configuration of the [Upstream](./architecture-design/upstream.md).                                                |                                                  |
| upstream_id      | False    | Upstream    | Id of the [Upstream](architecture-design/upstream.md) service.                                                     |                                                  |
| name             | False    | Auxiliary   | Identifier for the Service.                                                                                        | service-xxxx                                     |
| desc             | False    | Auxiliary   | Description of usage scenarios.                                                                                    | service xxxx                                     |
| labels           | False    | Match Rules | Attributes of the Service specified as key-value pairs.                                                            | {"version":"v2","build":"16","env":"production"} |
| enable_websocket | False    | Auxiliary   | Enables a websocket. Set to `false` by default.                                                                    |                                                  |
| hosts            | False    | Match Rules | Matches with any one of the multiple `host`s specified in the form of a non-empty list.                            | ["foo.com", "*.bar.com"]                         |
| create_time      | False    | Auxiliary   | Epoch timestamp (in seconds) of the created time. If missing, this field will be populated automatically.             | 1602883670                                       |
| update_time      | False    | Auxiliary   | Epoch timestamp (in seconds) of the updated time. If missing, this field will be populated automatically.             | 1602883670                                       |

Example configuration:

```shell
{
    "id": "1",                # id
    "plugins": {},            # Bound plugin
    "upstream_id": "1",       # upstream id, recommended
    "upstream": {},           # upstream, not recommended
    "name": "service-test",
    "desc": "hello world",
    "enable_websocket": true,
    "hosts": ["foo.com"]
}
```

Example API usage:

```shell
$ curl http://127.0.0.1:9080/apisix/admin/services/201  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -i -d '
{
    "plugins": {
        "limit-count": {
            "count": 2,
            "time_window": 60,
            "rejected_code": 503,
            "key": "remote_addr"
        }
    },
    "enable_websocket": true,
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'

HTTP/1.1 201 Created
...


# Add an upstream node to the Service
$ curl http://127.0.0.1:9080/apisix/admin/services/201 -H'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PATCH -i -d '
{
    "upstream": {
        "nodes": {
            "127.0.0.1:1981": 1
        }
    }
}'
HTTP/1.1 200 OK
...

After successful execution, upstream nodes will be updated to:
{
    "127.0.0.1:1980": 1,
    "127.0.0.1:1981": 1
}


# Update the weight of an upstream node to the Service
$ curl http://127.0.0.1:9080/apisix/admin/services/201 -H'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PATCH -i -d '
{
    "upstream": {
        "nodes": {
            "127.0.0.1:1981": 10
        }
    }
}'
HTTP/1.1 200 OK
...

After successful execution, upstream nodes will be updated to:
{
    "127.0.0.1:1980": 1,
    "127.0.0.1:1981": 10
}


# Delete an upstream node for the Service
$ curl http://127.0.0.1:9080/apisix/admin/services/201 -H'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PATCH -i -d '
{
    "upstream": {
        "nodes": {
            "127.0.0.1:1980": null
        }
    }
}'
HTTP/1.1 200 OK
...

After successful execution, upstream nodes will be updated to:
{
    "127.0.0.1:1981": 10
}


# Replace upstream nodes of the Service
$ curl http://127.0.0.1:9080/apisix/admin/services/201/upstream/nodes -H'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PATCH -i -d '
{
    "127.0.0.1:1982": 1
}'
HTTP/1.1 200 OK
...

After successful execution, upstream nodes will not retain the original data, and the entire update is:
{
    "127.0.0.1:1982": 1
}

```

### Response Parameters

Currently, the response is returned from etcd.

[Back to TOC](#table-of-contents)

## Consumer

**API**: /apisix/admin/consumers/{username}

Consumers are users of services and can only be used in conjunction with a user authentication system. A Consumer is identified by a `username` property. So, for creating a new Consumer, only the HTTP `PUT` method is supported.

### Request Methods

| Method | Request URI                        | Request Body | Description                                       |
| ------ | ---------------------------------- | ------------ | ------------------------------------------------- |
| GET    | /apisix/admin/consumers            | NULL         | Fetches a list of all Consumers.                  |
| GET    | /apisix/admin/consumers/{username} | NULL         | Fetches specified Consumer by username.           |
| PUT    | /apisix/admin/consumers            | {...}        | Create new Consumer.                              |
| DELETE | /apisix/admin/consumers/{username} | NULL         | Removes the Consumer with the specified username. |

### Request Body Parameters

| Parameter   | Required | Type        | Description                                                                                                        | Example                                          |
| ----------- | -------- | ----------- | ------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------ |
| username    | True     | Name        | Name of the Consumer.                                                                                              |                                                  |
| plugins     | False    | Plugin      | Plugins that are executed during the request/response cycle. See [Plugin](architecture-design/plugin.md) for more. |                                                  |
| desc        | False    | Auxiliary   | Description of usage scenarios.                                                                                    | customer xxxx                                    |
| labels      | False    | Match Rules | Attributes of the Consumer specified as key-value pairs.                                                           | {"version":"v2","build":"16","env":"production"} |
| create_time | False    | Auxiliary   | Epoch timestamp (in seconds) of the created time. If missing, this field will be populated automatically.             | 1602883670                                       |
| update_time | False    | Auxiliary   | Epoch timestamp (in seconds) of the updated time. If missing, this field will be populated automatically.             | 1602883670                                       |

Example Configuration:

```shell
{
    "plugins": {},          # Bound plugin
    "username": "name",     # Consumer name
    "desc": "hello world",  # Consumer desc
}
```

When bound to a Route or Service, the Authentication Plugin infers the Consumer from the request and does not require any parameters. Whereas, when it is bound to a Consumer, username, password and other information needs to be provided.

Example API usage:

```shell
$ curl http://127.0.0.1:9080/apisix/admin/consumers  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -i -d '
{
    "username": "jack",
    "plugins": {
        "key-auth": {
            "key": "auth-one"
        },
        "limit-count": {
            "count": 2,
            "time_window": 60,
            "rejected_code": 503,
            "key": "remote_addr"
        }
    }
}'
HTTP/1.1 200 OK
Date: Thu, 26 Dec 2019 08:17:49 GMT
...

{"node":{"value":{"username":"jack","plugins":{"key-auth":{"key":"auth-one"},"limit-count":{"time_window":60,"count":2,"rejected_code":503,"key":"remote_addr","policy":"local"}}},"createdIndex":64,"key":"\/apisix\/consumers\/jack","modifiedIndex":64},"prevNode":{"value":"{\"username\":\"jack\",\"plugins\":{\"key-auth\":{\"key\":\"auth-one\"},\"limit-count\":{\"time_window\":60,\"count\":2,\"rejected_code\":503,\"key\":\"remote_addr\",\"policy\":\"local\"}}}","createdIndex":63,"key":"\/apisix\/consumers\/jack","modifiedIndex":63},"action":"set"}
```

Since `v2.2`, we can bind multiple authentication plugins to the same consumer.

### Response Parameters

Currently, the response is returned from etcd.

[Back to TOC](#table-of-contents)

## Upstream

**API**: /apisix/admin/upstreams/{id}

Upstream is a virtual host abstraction that performs load balancing on a given set of service nodes according to the configured rules.

An Upstream configuration can be directly bound to a Route or a Service, but the configuration in Route has a higher priority. This behavior is consistent with priority followed by the Plugin object.

### Request Methods

| Method | Request URI                         | Request Body | Description                                                                                                                      |
| ------ | ----------------------------------- | ------------ | -------------------------------------------------------------------------------------------------------------------------------- |
| GET    | /apisix/admin/upstreams             | NULL         | Fetch a list of all configured Upstreams.                                                                                        |
| GET    | /apisix/admin/upstreams/{id}        | NULL         | Fetches specified Upstream by id.                                                                                                |
| PUT    | /apisix/admin/upstreams/{id}        | {...}        | Creates an Upstream with the specified id.                                                                                           |
| POST   | /apisix/admin/upstreams             | {...}        | Creates an Upstream and assigns a random id.                                                                                           |
| DELETE | /apisix/admin/upstreams/{id}        | NULL         | Removes the Upstream with the specified id.                                                                                      |
| PATCH  | /apisix/admin/upstreams/{id}        | {...}        | Updates the selected attributes of the specified, existing Upstream. To delete an attribute, set value of attribute set to null. |
| PATCH  | /apisix/admin/upstreams/{id}/{path} | {...}        | Updates the attribute specified in the path. The values of other attributes remain unchanged.                                    |

### Request Body Parameters

In addition to the equalization algorithm selections, Upstream also supports passive health check and retry for the upstream. See the table below for more details:

| Name                        | Optional                                    | Description                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      | Example                                                                                                                                    |
| --------------------------- | ------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| type                        | required                                    | Load balancing algorithm to be used.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |                                                                                                                                            |
| nodes                       | required, can't be used with `service_name` | IP addresses (with optional ports) of the Upstream nodes represented as a hash table or an array. In the hash table, the key is the IP address and the value is the weight of the node for the load balancing algorithm. In the array, each item is a hash table with keys `host`, `weight`, and the optional `port` and `priority`. Empty nodes are treated as placeholders and clients trying to access this Upstream will receive a 502 response.                                                                                                                                                                                                                                                                             | `192.168.1.100:80`                                                                                                                         |
| service_name                | required, can't be used with `nodes`        | Service name used for [service discovery](discovery.md).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         | `a-bootiful-client`                                                                                                                        |
| discovery_type              | required, if `service_name` is used         | The type of service [discovery](discovery.md).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   | `eureka`                                                                                                                                   |
| hash_on                     | optional                                    | Only valid if the `type` is `chash`. Supports Nginx variables (`vars`), custom headers (`header`), `cookie` and `consumer`. Defaults to `vars`.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |                                                                                                                                            |
| key                         | optional                                    | Only valid if the `type` is `chash`. Finds the corresponding node `id` according to `hash_on` and `key` values. When `hash_on` is set to `vars`, `key` is a required parameter and it supports [Nginx variables](http://nginx.org/en/docs/varindex.html). When `hash_on` is set as `header`, `key` is a required parameter, and `header name` can be customized. When `hash_on` is set to `cookie`, `key` is also a required parameter, and `cookie name` can be customized. When `hash_on` is set to `consumer`, `key` need not be set and the `key` used by the hash algorithm would be the authenticated `consumer_name`. If the specified `hash_on` and `key` fail to fetch the values, it will default to `remote_address`. | `uri`, `server_name`, `server_addr`, `request_uri`, `remote_port`, `remote_addr`, `query_string`, `host`, `hostname`, `arg_***`, `arg_***` |
| checks                      | optional                                    | Configures the parameters for the [health check](health-check.md).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |                                                                                                                                            |
| retries                     | optional                                    | Sets the number of retries while passing the request to Upstream using the underlying Nginx mechanism. Set according to the number of available backend nodes by default. Setting this to `0` disables retry.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |                                                                                                                                            |
| retry_timeout               | optional                                    | Timeout to continue with retries. Setting this to `0` disables the retry timeout.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |                                                                                                                                            |
| timeout                     | optional                                    | Sets the timeout for connecting to, and sending and receiving messages to and from the Upstream.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |                                                                                                                                            |
| name                        | optional                                    | Identifier for the Upstream.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |                                                                                                                                            |
| desc                        | optional                                    | Description of usage scenarios.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |                                                                                                                                            |
| pass_host                   | optional                                    | Configures the `host` when the request is forwarded to the upstream. Can be one of `pass`, `node` or `rewrite`. Defaults to `pass` if not specified. `pass`- transparently passes the client's host to the Upstream. `node`- uses the host configured in the node of the Upstream. `rewrite`- Uses the value configured in `upstream_host`.                                                                                                                                                                                                                                                                                                                                                                                      |                                                                                                                                            |
| upstream_host               | optional                                    | Specifies the host of the Upstream request. This is only valid if the `pass_host` is set to `rewrite`.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |                                                                                                                                            |
| scheme                      | optional                                    | The scheme used when communicating with the Upstream. For an L7 proxy, this value can be one of 'http', 'https', 'grpc', 'grpcs'. For an L4 proxy, this value could be one of 'tcp', 'udp', 'tls'. Defaults to 'http'.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |                                                                                                                                            |
| labels                      | optional                                    | Attributes of the Upstream specified as key-value pairs.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         | {"version":"v2","build":"16","env":"production"}                                                                                           |
| create_time                 | optional                                    | Epoch timestamp (in seconds) of the created time. If missing, this field will be populated automatically.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           | 1602883670                                                                                                                                 |
| update_time                 | optional                                    | Epoch timestamp (in seconds) of the updated time. If missing, this field will be populated automatically.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           | 1602883670                                                                                                                                 |
| tls.client_cert             | optional                                    | Sets the client certificate while connecting to a TLS Upstream.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |                                                                                                                                            |
| tls.client_key              | optional                                    | Sets the client private key while connecting to a TLS Upstream.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |                                                                                                                                            |
| keepalive_pool.size         | optional                                    | Sets `keepalive` directive dynamically.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |                                                                                                                                            |
| keepalive_pool.idle_timeout | optional                                    | Sets `keepalive_timeout` directive dynamically.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |                                                                                                                                            |
| keepalive_pool.requests     | optional                                    | Sets `keepalive_requests` directive dynamically.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |                                                                                                                                            |

An Upstream can be one of the following `types`:

- `roundrobin`: Round robin balancing with weights.
- `chash`: Consistent hash.
- `ewma`: Pick the node with minimum latency. See [EWMA Chart](https://en.wikipedia.org/wiki/EWMA_chart) for more details.
- `least_conn`: Picks the node with the lowest value of `(active_conn + 1) / weight`. Here, an active connection is a connection being used by the request and is similar to the concept in Nginx.
- user-defined load balancer loaded via `require("apisix.balancer.your_balancer")`.

The following should be considered when setting the `hash_on` value:

- When set to `vars`, a `key` is required. The value of the key can be any of the [Nginx variables](http://nginx.org/en/docs/varindex.html) without the `$` prefix.
- When set to `header`, a `key` is required. This is equal to "http\_`key`".
- When set to `cookie`, a `key` is required. This key is equal to "cookie\_`key`". The cookie name is case-sensitive.
- When set to `consumer`, the `key` is optional and the key is set to the `consumer_name` captured from the authentication Plugin.
- When set to `vars_combinations`, the `key` is required. The value of the key can be a combination of any of the [Nginx variables](http://nginx.org/en/docs/varindex.html) like `$request_uri$remote_addr`.
- When no value is set for either `hash_on` or `key`, the key defaults to `remote_addr`.

The features described below requires APISIX to be run on [APISIX-OpenResty](./how-to-build.md#step-6-build-openresty-for-apache-apisix):

You can set the `scheme` to `tls`, which means "TLS over TCP".

To use mTLS to communicate with Upstream, you can use the `tls.client_cert/key` in the same format as SSL's `cert` and `key` fields.

To allow Upstream to have a separate connection pool, use `keepalive_pool`. It can be configured by modifying its child fields.

Example Configuration:

```shell
{
    "id": "1",                  # id
    "retries": 1,               # retry times
    "timeout": {                # Set the timeout for connecting, sending and receiving messages.
        "connect":15,
        "send":15,
        "read":15,
    },
    "nodes": {"host:80": 100},  # Upstream machine address list, the format is `Address + Port`
                                # is the same as "nodes": [ {"host": "host", "port": 80, "weight": 100} ],
    "type":"roundrobin",
    "checks": {},               # Health check parameters
    "hash_on": "",
    "key": "",
    "name": "upstream-for-test",
    "desc": "hello world",
    "scheme": "http",           # The scheme used when communicating with upstream, the default is `http`
}
```

Example API usage:

Example 1: Create an Upstream and modify the data in `nodes`

```shell
# Create upstream
$ curl http://127.0.0.1:9080/apisix/admin/upstreams/100  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -i -X PUT -d '
{
    "type":"roundrobin",
    "nodes":{
        "127.0.0.1:1980": 1
    }
}'
HTTP/1.1 201 Created
...


# Add a node to the Upstream
$ curl http://127.0.0.1:9080/apisix/admin/upstreams/100 -H'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PATCH -i -d '
{
    "nodes": {
        "127.0.0.1:1981": 1
    }
}'
HTTP/1.1 200 OK
...

After successful execution, nodes will be updated to:
{
    "127.0.0.1:1980": 1,
    "127.0.0.1:1981": 1
}


# Update the weight of a node to the Upstream
$ curl http://127.0.0.1:9080/apisix/admin/upstreams/100 -H'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PATCH -i -d '
{
    "nodes": {
        "127.0.0.1:1981": 10
    }
}'
HTTP/1.1 200 OK
...

After successful execution, nodes will be updated to:
{
    "127.0.0.1:1980": 1,
    "127.0.0.1:1981": 10
}


# Delete a node for the Upstream
$ curl http://127.0.0.1:9080/apisix/admin/upstreams/100 -H'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PATCH -i -d '
{
    "nodes": {
        "127.0.0.1:1980": null
    }
}'
HTTP/1.1 200 OK
...

After successful execution, nodes will be updated to:
{
    "127.0.0.1:1981": 10
}


# Replace the nodes of the Upstream
$ curl http://127.0.0.1:9080/apisix/admin/upstreams/100/nodes -H'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PATCH -i -d '
{
    "127.0.0.1:1982": 1
}'
HTTP/1.1 200 OK
...

After the execution is successful, nodes will not retain the original data, and the entire update is:
{
    "127.0.0.1:1982": 1
}

```

Example 2: Proxy client request to `https` Upstream service

1. Create a route and configure the upstream scheme as `https`.

```shell
$ curl -i http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/get",
    "upstream": {
        "type": "roundrobin",
        "scheme": "https",
        "nodes": {
            "httpbin.org:443": 1
        }
    }
}'
```

After successful execution, the scheme when requesting to communicate with the upstream will be `https`.

2. Send a request to test.

```shell
$ curl http://127.0.0.1:9080/get
{
  "args": {},
  "headers": {
    "Accept": "*/*",
    "Host": "127.0.0.1",
    "User-Agent": "curl/7.29.0",
    "X-Amzn-Trace-Id": "Root=1-6058324a-0e898a7f04a5e95b526bb183",
    "X-Forwarded-Host": "127.0.0.1"
  },
  "origin": "127.0.0.1",
  "url": "https://127.0.0.1/get"
}
```

The request is successful, meaning that the proxy Upstream `https` is valid.

**Note**:

Each node can be configured with a priority. A node with low priority will only be
used when all the nodes with higher priority have been tried or are unavailable.

As the default priority is 0, nodes with negative priority can be configured as a backup.

For example:

```json
{
  "uri": "/hello",
  "upstream": {
    "type": "roundrobin",
    "nodes": [
      { "host": "127.0.0.1", "port": 1980, "weight": 2000 },
      { "host": "127.0.0.1", "port": 1981, "weight": 1, "priority": -1 }
    ],
    "checks": {
      "active": {
        "http_path": "/status",
        "healthy": {
          "interval": 1,
          "successes": 1
        },
        "unhealthy": {
          "interval": 1,
          "http_failures": 1
        }
      }
    }
  }
}
```

Node `127.0.0.2` will be used only after `127.0.0.1` is tried or unavailable.
It can therefore act as a backup for the node `127.0.0.1`.

### Response Parameters

Currently, the response is returned from etcd.

[Back to TOC](#table-of-contents)

## SSL

**API**:/apisix/admin/ssl/{id}

### Request Methods

| Method | Request URI            | Request Body | Description                                     |
| ------ | ---------------------- | ------------ | ----------------------------------------------- |
| GET    | /apisix/admin/ssl      | NULL         | Fetches a list of all configured SSL resources. |
| GET    | /apisix/admin/ssl/{id} | NULL         | Fetch specified resource by id.                 |
| PUT    | /apisix/admin/ssl/{id} | {...}        | Creates a resource with the specified id.           |
| POST   | /apisix/admin/ssl      | {...}        | Creates a resource and assigns a random id.           |
| DELETE | /apisix/admin/ssl/{id} | NULL         | Removes the resource with the specified id.     |

### Request Body Parameters

| Parameter    | Required | Type                     | Description                                                                                                    | Example                                          |
| ------------ | -------- | ------------------------ | -------------------------------------------------------------------------------------------------------------- | ------------------------------------------------ |
| cert         | True     | Certificate              | HTTPS certificate.                                                                                             |                                                  |
| key          | True     | Private key              | HTTPS private key.                                                                                             |                                                  |
| certs        | False    | An array of certificates | Used for configuring multiple certificates for the same domain excluding the one provided in the `cert` field. |                                                  |
| keys         | False    | An array of private keys | Private keys to pair with the `certs`.                                                                         |                                                  |
| client.ca    | False    | Certificate              | Sets the CA certificate that verifies the client. Requires OpenResty 1.19+.                                    |                                                  |
| client.depth | False    | Certificate              | Sets the verification depth in client certificate chains. Defaults to 1. Requires OpenResty 1.19+.             |                                                  |
| snis         | True     | Match Rules              | A non-empty array of HTTPS SNI                                                                                 |                                                  |
| labels       | False    | Match Rules              | Attributes of the resource specified as key-value pairs.                                                       | {"version":"v2","build":"16","env":"production"} |
| create_time  | False    | Auxiliary                | Epoch timestamp (in seconds) of the created time. If missing, this field will be populated automatically.         | 1602883670                                       |
| update_time  | False    | Auxiliary                | Epoch timestamp (in seconds) of the updated time. If missing, this field will be populated automatically.         | 1602883670                                       |
| status       | False    | Auxiliary                | Enables the current SSL. Set to `1` (enabled) by default.                                                      | `1` to enable, `0` to disable                    |

Example Configuration:

```shell
{
    "id": "1",           # id
    "cert": "cert",      # Certificate
    "key": "key",        # Private key
    "snis": ["t.com"]    # https SNI
}
```

See [Certificate](./certificate.md) for more examples.

## Global Rule

**API**: /apisix/admin/global_rules/{id}

Sets Plugins which run globally. i.e these Plugins will be run before any Route/Service level Plugins.

### Request Methods

| Method | Request URI                            | Request Body | Description                                                                                                                         |
| ------ | -------------------------------------- | ------------ | ----------------------------------------------------------------------------------------------------------------------------------- |
| GET    | /apisix/admin/global_rules             | NULL         | Fetches a list of all Global Rules.                                                                                                 |
| GET    | /apisix/admin/global_rules/{id}        | NULL         | Fetches specified Global Rule by id.                                                                                                |
| PUT    | /apisix/admin/global_rules/{id}        | {...}        | Creates a Global Rule with the specified id.                                                                                        |
| DELETE | /apisix/admin/global_rules/{id}        | NULL         | Removes the Global Rule with the specified id.                                                                                      |
| PATCH  | /apisix/admin/global_rules/{id}        | {...}        | Updates the selected attributes of the specified, existing Global Rule. To delete an attribute, set value of attribute set to null. |
| PATCH  | /apisix/admin/global_rules/{id}/{path} | {...}        | Updates the attribute specified in the path. The values of other attributes remain unchanged.                                       |

### Request Body Parameters

| Parameter   | Required | Description                                                                                                        | Example    |
| ----------- | -------- | ------------------------------------------------------------------------------------------------------------------ | ---------- |
| plugins     | True     | Plugins that are executed during the request/response cycle. See [Plugin](architecture-design/plugin.md) for more. |            |
| create_time | False    | Epoch timestamp (in seconds) of the created time. If missing, this field will be populated automatically.             | 1602883670 |
| update_time | False    | Epoch timestamp (in seconds) of the updated time. If missing, this field will be populated automatically.             | 1602883670 |

## Plugin config

**API**: /apisix/admin/plugin_configs/{id}

Group of Plugins which can be reused across Routes.

### Request Methods

| Method | Request URI                              | Request Body | Description                                                                                                                           |
| ------ | ---------------------------------------- | ------------ | ------------------------------------------------------------------------------------------------------------------------------------- |
| GET    | /apisix/admin/plugin_configs             | NULL         | Fetches a list of all Plugin configs.                                                                                                 |
| GET    | /apisix/admin/plugin_configs/{id}        | NULL         | Fetches specified Plugin config by id.                                                                                                |
| PUT    | /apisix/admin/plugin_configs/{id}        | {...}        | Creates a new Plugin config with the specified id.                                                                                    |
| DELETE | /apisix/admin/plugin_configs/{id}        | NULL         | Removes the Plugin config with the specified id.                                                                                      |
| PATCH  | /apisix/admin/plugin_configs/{id}        | {...}        | Updates the selected attributes of the specified, existing Plugin config. To delete an attribute, set value of attribute set to null. |
| PATCH  | /apisix/admin/plugin_configs/{id}/{path} | {...}        | Updates the attribute specified in the path. The values of other attributes remain unchanged.                                         |

### Request Body Parameters

| Parameter   | Required | Description                                                                                                        | Example                                          |
| ----------- | -------- | ------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------ |
| plugins     | True     | Plugins that are executed during the request/response cycle. See [Plugin](architecture-design/plugin.md) for more. |                                                  |
| desc        | False    | Description of usage scenarios.                                                                                    | customer xxxx                                    |
| labels      | False    | Attributes of the Plugin config specified as key-value pairs.                                                      | {"version":"v2","build":"16","env":"production"} |
| create_time | False    | Epoch timestamp (in seconds) of the created time. If missing, this field will be populated automatically.             | 1602883670                                       |
| update_time | False    | Epoch timestamp (in seconds) of the updated time. If missing, this field will be populated automatically.             | 1602883670                                       |

[Back to TOC](#table-of-contents)

## Plugin Metadata

**API**: /apisix/admin/plugin_metadata/{plugin_name}

### Request Methods

| Method | Request URI                                 | Request Body | Description                                                     |
| ------ | ------------------------------------------- | ------------ | --------------------------------------------------------------- |
| GET    | /apisix/admin/plugin_metadata/{plugin_name} | NULL         | Fetches the metadata of the specified Plugin by `plugin_name`.  |
| PUT    | /apisix/admin/plugin_metadata/{plugin_name} | {...}        | Creates metadata for the Plugin specified by the `plugin_name`. |
| DELETE | /apisix/admin/plugin_metadata/{plugin_name} | NULL         | Removes metadata for the Plugin specified by the `plugin_name`. |

### Request Body Parameters

A JSON object defined according to the `metadata_schema` of the Plugin ({plugin_name}).

Example Configuration:

```shell
$ curl http://127.0.0.1:9080/apisix/admin/plugin_metadata/example-plugin  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -i -X PUT -d '
{
    "skey": "val",
    "ikey": 1
}'
HTTP/1.1 201 Created
Date: Thu, 26 Dec 2019 04:19:34 GMT
Content-Type: text/plain
```

[Back to TOC](#table-of-contents)

## Plugin

**API**: /apisix/admin/plugins/{plugin_name}

### Request Methods

| Method | Request URI                         | Request Body | Description                                    |
| ------ | ----------------------------------- | ------------ | ---------------------------------------------- |
| GET    | /apisix/admin/plugins/list          | NULL         | Fetches a list of all Plugins.                 |
| GET    | /apisix/admin/plugins/{plugin_name} | NULL         | Fetches the specified Plugin by `plugin_name`. |

### Request Body Parameters

The Plugin ({plugin_name}) of the data structure.

Example API usage:

```shell
$ curl "http://127.0.0.1:9080/apisix/admin/plugins/list" -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1'
["zipkin","request-id",...]

$ curl "http://127.0.0.1:9080/apisix/admin/plugins/key-auth" -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1'
{"properties":{"disable":{"type":"boolean"}},"additionalProperties":false,"type":"object"}
```

**API**: /apisix/admin/plugins?all=true

Get all attributes from all Plugins. Each Plugin has the attributes `name`, `priority`, `type`, `schema`, `consumer_schema` and `version`. Defaults to only HTTP Plugins.

If you need to get attributes from stream Plugins, use `/apisix/admin/plugins?all=true&subsystem=stream`.

### Request Methods

| Method | Request URI                    | Request Body | Description                              |
| ------ | ------------------------------ | ------------ | ---------------------------------------- |
| GET    | /apisix/admin/plugins?all=true | NULL         | Fetches all attributes from all Plugins. |

### Request Arguments

| Name      | Description                   | Default |
| --------- | ----------------------------- | ------- |
| subsystem | The subsystem of the Plugins. | http    |

[Back to TOC](#table-of-contents)

## Stream Route

**API**: /apisix/admin/stream_routes/{id}

Route used in the [Stream Proxy](./stream-proxy.md).

### Request Methods

| Method | Request URI                      | Request Body | Description                                     |
| ------ | -------------------------------- | ------------ | ----------------------------------------------- |
| GET    | /apisix/admin/stream_routes      | NULL         | Fetches a list of all configured Stream Routes. |
| GET    | /apisix/admin/stream_routes/{id} | NULL         | Fetches specified Stream Route by id.           |
| PUT    | /apisix/admin/stream_routes/{id} | {...}        | Creates a Stream Route with the specified id.       |
| POST   | /apisix/admin/stream_routes      | {...}        | Creates a Stream Route and assigns a random id.       |
| DELETE | /apisix/admin/stream_routes/{id} | NULL         | Removes the Stream Route with the specified id. |

### Request Body Parameters

| Parameter   | Required | Type     | Description                                                         | Example                       |
| ----------- | -------- | -------- | ------------------------------------------------------------------- | ----------------------------- |
| upstream    | False    | Upstream | Configuration of the [Upstream](./architecture-design/upstream.md). |                               |
| upstream_id | False    | Upstream | Id of the [Upstream](architecture-design/upstream.md) service.      |                               |
| remote_addr | False    | IP/CIDR  | Filters Upstream forwards by matching with client IP.               | "127.0.0.1/32" or "127.0.0.1" |
| server_addr | False    | IP/CIDR  | Filters Upstream forwards by matching with APISIX Server IP.        | "127.0.0.1/32" or "127.0.0.1" |
| server_port | False    | Integer  | Filters Upstream forwards by matching with APISIX Server port.      | 9090                          |
| sni         | False    | Host     | Server Name Indication.                                             | "test.com"                    |

To learn more about filtering in stream proxies, check [this](./stream-proxy.md#more-route-match-options) document.

[Back to TOC](#table-of-contents)
