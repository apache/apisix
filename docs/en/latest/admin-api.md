---
title: Admin API
keywords:
  - APISIX
  - API Gateway
  - Admin API
  - Route
  - Plugin
  - Upstream
description: This article introduces the functions supported by the Apache APISIX Admin API, which you can use to get, create, update, and delete resources.
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

The Admin API lets users control their deployed Apache APISIX instance. The [architecture design](./architecture-design/apisix.md) gives an idea about how everything fits together.

## Configuration

When APISIX is started, the Admin API will listen on port `9180` by default and take the API prefixed with `/apisix/admin`.

Therefore, to avoid conflicts between your designed API and `/apisix/admin`, you can modify the configuration file [`/conf/config.yaml`](https://github.com/apache/apisix/blob/master/conf/config.yaml) to modify the default listening port.

APISIX supports setting the IP access allowlist of Admin API to prevent APISIX from being illegally accessed and attacked. You can configure the IP addresses to allow access in the `deployment.admin.allow_admin` option in the `./conf/config.yaml` file.

The `X-API-KEY` shown below refers to the `deployment.admin.admin_key.key` in the `./conf/config.yaml` file, which is the access token for the Admin API.

:::tip

For security reasons, please modify the default `admin_key`, and check the `allow_admin` IP access list.

:::

```yaml title="./conf/config.yaml"
deployment:
    admin:
        admin_key:
        - name: admin
            key: edd1c9f034335f136f87ad84b625c8f1  # using fixed API token has security risk, please update it when you deploy to production environment
            role: admin
        allow_admin:                    # http://nginx.org/en/docs/http/ngx_http_access_module.html#allow
            - 127.0.0.0/24
        admin_listen:
            ip: 0.0.0.0                 # Specific IP, if not set, the default value is `0.0.0.0`.
            port: 9180                  # Specific port, which must be different from node_listen's port.
```

## V3 new feature

The Admin API has made some breaking changes in V3 version, as well as supporting additional features.

### Support new response body format

1. Remove `action` field in response body;
2. Adjust the response body structure when fetching the list of resources, the new response body structure like:

Return single resource:

```json
{
  "modifiedIndex": 2685183,
  "value": {
    "id": "1",
    ...
  },
  "key": "/apisix/routes/1",
  "createdIndex": 2684956
}
```

Return multiple resources:

```json
{
  "list": [
    {
      "modifiedIndex": 2685183,
      "value": {
        "id": "1",
        ...
      },
      "key": "/apisix/routes/1",
      "createdIndex": 2684956
    },
    {
      "modifiedIndex": 2685163,
      "value": {
        "id": "2",
        ...
      },
      "key": "/apisix/routes/2",
      "createdIndex": 2685163
    }
  ],
  "total": 2
}
```

### Support paging query

Paging query is supported when getting the resource list, paging parameters include:

| parameter | Default | Valid range | Description                   |
| --------- | ------  | ----------- | ----------------------------- |
| page      | 1       | [1, ...]    | Number of pages.              |
| page_size |         | [10, 500]   | Number of resources per page. |

The example is as follows:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes?page=1&page_size=10" \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X GET
```

```json
{
  "total": 1,
  "list": [
    {
      ...
    }
  ]
}
```

Resources that support paging queries:

- Consumer
- Consumer Group
- Global Rules
- Plugin Config
- Proto
- Route
- Service
- SSL
- Stream Route
- Upstream
- Secret

### Support filtering query

When getting a list of resources, it supports filtering resources based on `name`, `label`, `uri`.

| parameter | parameter                                                    |
| --------- | ------------------------------------------------------------ |
| name      | Query resource by their `name`, which will not appear in the query results if the resource itself does not have `name`. |
| label     | Query resource by their `label`, which will not appear in the query results if the resource itself does not have `label`. |
| uri       | Supported on Route resources only. If the `uri` of a Route is equal to the uri of the query or if the `uris` contains the uri of the query, the Route resource appears in the query results. |

:::tip

When multiple filter parameters are enabled, use the intersection of the query results for different filter parameters.

:::

The following example will return a list of routes, and all routes in the list satisfy: the `name` of the route contains the string "test", the `uri` contains the string "foo", and there is no restriction on the `label` of the route, since the label of the query is the empty string.

```shell
curl 'http://127.0.0.1:9180/apisix/admin/routes?name=test&uri=foo&label=' \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X GET
```

```json
{
  "total": 1,
  "list": [
    {
      ...
    }
  ]
}
```

## Route

[Routes](./terminology/route.md) match the client's request based on defined rules, loads and executes the corresponding [plugins](#plugin), and forwards the request to the specified [Upstream](#upstream).

### Route API

Route resource request address: /apisix/admin/routes/{id}?ttl=0

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
| uri              | True, can't be used with `uris`          | Match Rules | Matches the uri. For more advanced matching see [Router](./terminology/router.md).                                                                                                                                                                                                     | "/hello"                                             |
| uris             | True, can't be used with `uri`           | Match Rules | Matches with any one of the multiple `uri`s specified in the form of a non-empty list.                                                                                                                                                                                                         | ["/hello", "/word"]                                  |
| host             | False, can't be used with `hosts`        | Match Rules | Matches with domain names such as `foo.com` or PAN domain names like `*.foo.com`.                                                                                                                                                                                                              | "foo.com"                                            |
| hosts            | False, can't be used with `host`         | Match Rules | Matches with any one of the multiple `host`s specified in the form of a non-empty list.                                                                                                                                                                                                        | ["foo.com", "*.bar.com"]                             |
| remote_addr      | False, can't be used with `remote_addrs` | Match Rules | Matches with the specified IP address in standard IPv4 format (`192.168.1.101`), CIDR format (`192.168.1.0/24`), or in IPv6 format (`::1`, `fe80::1`, `fe80::1/64`).                                                                                                                           | "192.168.1.0/24"                                     |
| remote_addrs     | False, can't be used with `remote_addr`  | Match Rules | Matches with any one of the multiple `remote_addr`s specified in the form of a non-empty list.                                                                                                                                                                                                 | ["127.0.0.1", "192.0.0.0/8", "::1"]                  |
| methods          | False                                    | Match Rules | Matches with the specified methods. Matches all methods if empty or unspecified.                                                                                                                                                                                                               | ["GET", "POST"]                                      |
| priority         | False                                    | Match Rules | If different Routes matches to the same `uri`, then the Route is matched based on its `priority`. A higher value corresponds to higher priority. It is set to `0` by default.                                                                                                                  | priority = 10                                        |
| vars             | False                                    | Match Rules | Matches based on the specified variables consistent with variables in Nginx. Takes the form `[[var, operator, val], [var, operator, val], ...]]`. Note that this is case sensitive when matching a cookie name. See [lua-resty-expr](https://github.com/api7/lua-resty-expr) for more details. | [["arg_name", "==", "json"], ["arg_age", ">", 18]]   |
| filter_func      | False                                    | Match Rules | Matches based on a user-defined filtering function. Used in scenarios requiring complex matching. These functions can accept an input parameter `vars` which can be used to access the Nginx variables.                                                                                        | function(vars) return vars["arg_name"] == "json" end |
| plugins          | False                                    | Plugin      | Plugins that are executed during the request/response cycle. See [Plugin](terminology/plugin.md) for more.                                                                                                                                                                             |                                                      |
| script           | False                                    | Script      | Used for writing arbitrary Lua code or directly calling existing plugins to be executed. See [Script](terminology/script.md) for more.                                                                                                                                                 |                                                      |
| upstream         | False                                    | Upstream    | Configuration of the [Upstream](./terminology/upstream.md).                                                                                                                                                                                                                            |                                                      |
| upstream_id      | False                                    | Upstream    | Id of the [Upstream](terminology/upstream.md) service.                                                                                                                                                                                                                                 |                                                      |
| service_id       | False                                    | Service     | Configuration of the bound [Service](terminology/service.md).                                                                                                                                                                                                                          |                                                      |
| plugin_config_id | False, can't be used with `script`       | Plugin      | [Plugin config](terminology/plugin-config.md) bound to the Route.                                                                                                                                                                                                                      |                                                      |
| labels           | False                                    | Match Rules | Attributes of the Route specified as key-value pairs.                                                                                                                                                                                                                                          | {"version":"v2","build":"16","env":"production"}     |
| timeout          | False                                    | Auxiliary   | Sets the timeout (in seconds) for connecting to, and sending and receiving messages between the Upstream and the Route. This will overwrite the `timeout` value configured in your [Upstream](#upstream).                                                                                                   | {"connect": 3, "send": 3, "read": 3}                 |
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
    "filter_func": ""                     # User-defined filtering function
}
```

### Example API usage

- Create a route

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -i -d '
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
    ```

    ```shell
    HTTP/1.1 201 Created
    Date: Sat, 31 Aug 2019 01:17:15 GMT
    ...
    ```

- Create a route expires after 60 seconds, then it's deleted automatically

    ```shell
    curl 'http://127.0.0.1:9180/apisix/admin/routes/2?ttl=60' \
    -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -i -d '
    {
        "uri": "/aa/index.html",
        "upstream": {
            "type": "roundrobin",
            "nodes": {
                "127.0.0.1:1980": 1
            }
        }
    }'
    ```

    ```shell
    HTTP/1.1 201 Created
    Date: Sat, 31 Aug 2019 01:17:15 GMT
    ...
    ```

- Add an upstream node to the Route

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/routes/1 \
    -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PATCH -i -d '
    {
        "upstream": {
            "nodes": {
                "127.0.0.1:1981": 1
            }
        }
    }'
    ```

    ```shell
    HTTP/1.1 200 OK
    ...
    ```

    After successful execution, upstream nodes will be updated to:

    ```shell
    {
        "127.0.0.1:1980": 1,
        "127.0.0.1:1981": 1
    }
    ```

- Update the weight of an upstream node to the Route

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/routes/1 \
    -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PATCH -i -d '
    {
        "upstream": {
            "nodes": {
                "127.0.0.1:1981": 10
            }
        }
    }'
    ```

    ```shell
    HTTP/1.1 200 OK
    ...
    ```

    After successful execution, upstream nodes will be updated to:

    ```shell
    {
        "127.0.0.1:1980": 1,
        "127.0.0.1:1981": 10
    }
    ```

- Delete an upstream node for the Route

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/routes/1 \
    -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PATCH -i -d '
    {
        "upstream": {
            "nodes": {
                "127.0.0.1:1980": null
            }
        }
    }'
    ```

    ```shell
    HTTP/1.1 200 OK
    ...
    ```

    After successful execution, upstream nodes will be updated to:

    ```shell
    {
        "127.0.0.1:1981": 10
    }
    ```

- Replace methods of the Route  --  array

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/routes/1 \
    -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PATCH -i -d '{
        "methods": ["GET", "POST"]
    }'
    ```

    ```shell
    HTTP/1.1 200 OK
    ...
    ```

    After successful execution, methods will not retain the original data, and the entire update is:

    ```shell
    ["GET", "POST"]
    ```

- Replace upstream nodes of the Route -- sub path

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/routes/1/upstream/nodes \
    -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PATCH -i -d '
    {
        "127.0.0.1:1982": 1
    }'
    ```

    ```shell
    HTTP/1.1 200 OK
    ...
    ```

    After successful execution, nodes will not retain the original data, and the entire update is:

    ```shell
    {
        "127.0.0.1:1982": 1
    }
    ```

- Replace methods of the Route -- sub path

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/routes/1/methods \
    -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PATCH -i -d'["POST", "DELETE", " PATCH"]'
    ```

    ```shell
    HTTP/1.1 200 OK
    ...
    ```

    After successful execution, methods will not retain the original data, and the entire update is:

    ```shell
    ["POST", "DELETE", "PATCH"]
    ```

- Disable route

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/routes/1 \
    -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PATCH -i -d '
    {
        "status": 0
    }'
    ```

    ```shell
    HTTP/1.1 200 OK
    ...
    ```

    After successful execution, status nodes will be updated to:

    ```shell
    {
        "status": 0
    }
    ```

- Enable route

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/routes/1 \
    -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PATCH -i -d '
    {
        "status": 1
    }'
    ```

    ```shell
    HTTP/1.1 200 OK
    ...
    ```

    After successful execution, status nodes will be updated to:

    ```shell
    {
        "status": 1
    }
    ```

### Response Parameters

Currently, the response is returned from etcd.

## Service

A Service is an abstraction of an API (which can also be understood as a set of Route abstractions). It usually corresponds to an upstream service abstraction.

The relationship between Routes and a Service is usually N:1.

### Service API

Service resource request address: /apisix/admin/services/{id}

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
| plugins          | False    | Plugin      | Plugins that are executed during the request/response cycle. See [Plugin](terminology/plugin.md) for more. |                                                  |
| upstream         | False    | Upstream    | Configuration of the [Upstream](./terminology/upstream.md).                                                |                                                  |
| upstream_id      | False    | Upstream    | Id of the [Upstream](terminology/upstream.md) service.                                                     |                                                  |
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

### Example API usage

- Create a service

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/services/201  \
    -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -i -d '
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
    ```

    ```shell
    HTTP/1.1 201 Created
    ...
    ```

- Add an upstream node to the Service

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/services/201 \
    -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PATCH -i -d '
    {
        "upstream": {
            "nodes": {
                "127.0.0.1:1981": 1
            }
        }
    }'
    ```

    ```shell
    HTTP/1.1 200 OK
    ...
    ```

    After successful execution, upstream nodes will be updated to:

    ```shell
    {
        "127.0.0.1:1980": 1,
        "127.0.0.1:1981": 1
    }
    ```

- Update the weight of an upstream node to the Service

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/services/201 \
    -H'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PATCH -i -d '
    {
        "upstream": {
            "nodes": {
                "127.0.0.1:1981": 10
            }
        }
    }'
    ```

    ```shell
    HTTP/1.1 200 OK
    ...
    ```

    After successful execution, upstream nodes will be updated to:

    ```shell
    {
        "127.0.0.1:1980": 1,
        "127.0.0.1:1981": 10
    }
    ```

- Delete an upstream node for the Service

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/services/201 \
    -H'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PATCH -i -d '
    {
        "upstream": {
            "nodes": {
                "127.0.0.1:1980": null
            }
        }
    }'
    ```

    ```shell
    HTTP/1.1 200 OK
    ...
    ```

    After successful execution, upstream nodes will be updated to:

    ```shell
    {
        "127.0.0.1:1981": 10
    }
    ```

- Replace upstream nodes of the Service

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/services/201/upstream/nodes \
    -H'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PATCH -i -d '
    {
        "127.0.0.1:1982": 1
    }'
    ```

    ```shell
    HTTP/1.1 200 OK
    ...
    ```

    After successful execution, upstream nodes will not retain the original data, and the entire update is:

    ```shell
    {
        "127.0.0.1:1982": 1
    }
    ```

### Response Parameters

Currently, the response is returned from etcd.

## Consumer

Consumers are users of services and can only be used in conjunction with a user authentication system. A Consumer is identified by a `username` property. So, for creating a new Consumer, only the HTTP `PUT` method is supported.

### Consumer API

Consumer resource request address: /apisix/admin/consumers/{username}

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
| group_id    | False    | Name        | Group of the Consumer.                                                                                              |                                                  |
| plugins     | False    | Plugin      | Plugins that are executed during the request/response cycle. See [Plugin](terminology/plugin.md) for more. |                                                  |
| desc        | False    | Auxiliary   | Description of usage scenarios.                                                                                    | customer xxxx                                    |
| labels      | False    | Match Rules | Attributes of the Consumer specified as key-value pairs.                                                           | {"version":"v2","build":"16","env":"production"} |
| create_time | False    | Auxiliary   | Epoch timestamp (in seconds) of the created time. If missing, this field will be populated automatically.             | 1602883670                                       |
| update_time | False    | Auxiliary   | Epoch timestamp (in seconds) of the updated time. If missing, this field will be populated automatically.             | 1602883670                                       |

Example Configuration:

```shell
{
    "plugins": {},          # Bound plugin
    "username": "name",     # Consumer name
    "desc": "hello world"   # Consumer desc
}
```

When bound to a Route or Service, the Authentication Plugin infers the Consumer from the request and does not require any parameters. Whereas, when it is bound to a Consumer, username, password and other information needs to be provided.

### Example API usage

```shell
curl http://127.0.0.1:9180/apisix/admin/consumers  \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -i -d '
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
```

```shell
HTTP/1.1 200 OK
Date: Thu, 26 Dec 2019 08:17:49 GMT
...

{"node":{"value":{"username":"jack","plugins":{"key-auth":{"key":"auth-one"},"limit-count":{"time_window":60,"count":2,"rejected_code":503,"key":"remote_addr","policy":"local"}}},"createdIndex":64,"key":"\/apisix\/consumers\/jack","modifiedIndex":64},"prevNode":{"value":"{\"username\":\"jack\",\"plugins\":{\"key-auth\":{\"key\":\"auth-one\"},\"limit-count\":{\"time_window\":60,\"count\":2,\"rejected_code\":503,\"key\":\"remote_addr\",\"policy\":\"local\"}}}","createdIndex":63,"key":"\/apisix\/consumers\/jack","modifiedIndex":63}}
```

Since `v2.2`, we can bind multiple authentication plugins to the same consumer.

### Response Parameters

Currently, the response is returned from etcd.

## Upstream

Upstream is a virtual host abstraction that performs load balancing on a given set of service nodes according to the configured rules.

An Upstream configuration can be directly bound to a Route or a Service, but the configuration in Route has a higher priority. This behavior is consistent with priority followed by the Plugin object.

### Upstream API

Upstream resource request address: /apisix/admin/upstreams/{id}

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
| --------------------------- | ------------------------------------------- |----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------| ------------------------------------------------------------------------------------------------------------------------------------------ |
| type                        | optional                                    | Load balancing algorithm to be used, and the default value is `roundrobin`.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |                                                                                                                                            |
| nodes                       | required, can't be used with `service_name` | IP addresses (with optional ports) of the Upstream nodes represented as a hash table or an array. In the hash table, the key is the IP address and the value is the weight of the node for the load balancing algorithm. For hash table case, if the key is IPv6 address with port, then the IPv6 address must be quoted with square brackets. In the array, each item is a hash table with keys `host`, `weight`, and the optional `port` and `priority`. Empty nodes are treated as placeholders and clients trying to access this Upstream will receive a 502 response.                                                                                                                                                       | `192.168.1.100:80`, `[::1]:80`                                                                                                                         |
| service_name                | required, can't be used with `nodes`        | Service name used for [service discovery](discovery.md).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         | `a-bootiful-client`                                                                                                                        |
| discovery_type              | required, if `service_name` is used         | The type of service [discovery](discovery.md).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   | `eureka`                                                                                                                                   |
| hash_on                     | optional                                    | Only valid if the `type` is `chash`. Supports Nginx variables (`vars`), custom headers (`header`), `cookie` and `consumer`. Defaults to `vars`.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |                                                                                                                                            |
| key                         | optional                                    | Only valid if the `type` is `chash`. Finds the corresponding node `id` according to `hash_on` and `key` values. When `hash_on` is set to `vars`, `key` is a required parameter and it supports [Nginx variables](http://nginx.org/en/docs/varindex.html). When `hash_on` is set as `header`, `key` is a required parameter, and `header name` can be customized. When `hash_on` is set to `cookie`, `key` is also a required parameter, and `cookie name` can be customized. When `hash_on` is set to `consumer`, `key` need not be set and the `key` used by the hash algorithm would be the authenticated `consumer_name`. If the specified `hash_on` and `key` fail to fetch the values, it will default to `remote_addr`. | `uri`, `server_name`, `server_addr`, `request_uri`, `remote_port`, `remote_addr`, `query_string`, `host`, `hostname`, `arg_***`, `arg_***` |
| checks                      | optional                                    | Configures the parameters for the [health check](./tutorials/health-check.md).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |                                                                                                                                            |
| retries                     | optional                                    | Sets the number of retries while passing the request to Upstream using the underlying Nginx mechanism. Set according to the number of available backend nodes by default. Setting this to `0` disables retry.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |                                                                                                                                            |
| retry_timeout               | optional                                    | Timeout to continue with retries. Setting this to `0` disables the retry timeout.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |                                                                                                                                            |
| timeout                     | optional                                    | Sets the timeout (in seconds) for connecting to, and sending and receiving messages to and from the Upstream.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |                                                                                                                                            |
| name                        | optional                                    | Identifier for the Upstream.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |                                                                                                                                            |
| desc                        | optional                                    | Description of usage scenarios.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |                                                                                                                                            |
| pass_host                   | optional                                    | Configures the `host` when the request is forwarded to the upstream. Can be one of `pass`, `node` or `rewrite`. Defaults to `pass` if not specified. `pass`- transparently passes the client's host to the Upstream. `node`- uses the host configured in the node of the Upstream. `rewrite`- Uses the value configured in `upstream_host`.                                                                                                                                                                                                                                                                                                                                                                                      |                                                                                                                                            |
| upstream_host               | optional                                    | Specifies the host of the Upstream request. This is only valid if the `pass_host` is set to `rewrite`.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |                                                                                                                                            |
| scheme                      | optional                                    | The scheme used when communicating with the Upstream. For an L7 proxy, this value can be one of `http`, `https`, `grpc`, `grpcs`. For an L4 proxy, this value could be one of `tcp`, `udp`, `tls`. Defaults to `http`.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |                                                                                                                                            |
| labels                      | optional                                    | Attributes of the Upstream specified as `key-value` pairs.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         | {"version":"v2","build":"16","env":"production"}                                                                                           |
| create_time                 | optional                                    | Epoch timestamp (in seconds) of the created time. If missing, this field will be populated automatically.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           | 1602883670                                                                                                                                 |
| update_time                 | optional                                    | Epoch timestamp (in seconds) of the updated time. If missing, this field will be populated automatically.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           | 1602883670                                                                                                                                 |
| tls.client_cert             | optional, can't be used with `tls.client_cert_id`       | Sets the client certificate while connecting to a TLS Upstream.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |                                                                                                                                            |
| tls.client_key              | optional, can't be used with `tls.client_cert_id`       | Sets the client private key while connecting to a TLS Upstream.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |                                                                                                                                            |
| tls.client_cert_id          | optional, can't be used with `tls.client_cert` and `tls.client_key`       | Set the referenced [SSL](#ssl) id.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |                                                                                                                                            |
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

The features described below requires APISIX to be run on [APISIX-Base](./FAQ.md#how-do-i-build-the-apisix-base-environment):

You can set the `scheme` to `tls`, which means "TLS over TCP".

To use mTLS to communicate with Upstream, you can use the `tls.client_cert/key` in the same format as SSL's `cert` and `key` fields.

Or you can reference SSL object by `tls.client_cert_id` to set SSL cert and key. The SSL object can be referenced only if the `type` field is `client`, otherwise the request will be rejected by APISIX. In addition, only `cert` and `key` will be used in the SSL object.

To allow Upstream to have a separate connection pool, use `keepalive_pool`. It can be configured by modifying its child fields.

Example Configuration:

```shell
{
    "id": "1",                  # id
    "retries": 1,               # retry times
    "timeout": {                # Set the timeout for connecting, sending and receiving messages, each is 15 seconds.
        "connect":15,
        "send":15,
        "read":15
    },
    "nodes": {"host:80": 100},  # Upstream machine address list, the format is `Address + Port`
                                # is the same as "nodes": [ {"host": "host", "port": 80, "weight": 100} ],
    "type":"roundrobin",
    "checks": {},               # Health check parameters
    "hash_on": "",
    "key": "",
    "name": "upstream-for-test",
    "desc": "hello world",
    "scheme": "http"            # The scheme used when communicating with upstream, the default is `http`
}
```

### Example API usage

#### Create an Upstream and modify the data in `nodes`

1. Create upstream

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/upstreams/100  \
    -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -i -X PUT -d '
    {
        "type":"roundrobin",
        "nodes":{
            "127.0.0.1:1980": 1
        }
    }'
    ```

    ```shell
    HTTP/1.1 201 Created
    ...
    ```

2. Add a node to the Upstream

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/upstreams/100 \
    -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PATCH -i -d '
    {
        "nodes": {
            "127.0.0.1:1981": 1
        }
    }'
    ```

    ```
    HTTP/1.1 200 OK
    ...
    ```

    After successful execution, nodes will be updated to:

    ```shell
    {
        "127.0.0.1:1980": 1,
        "127.0.0.1:1981": 1
    }
    ```

3. Update the weight of a node to the Upstream

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/upstreams/100 \
    -H'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PATCH -i -d '
    {
        "nodes": {
            "127.0.0.1:1981": 10
        }
    }'
    ```

    ```shell
    HTTP/1.1 200 OK
    ...
    ```

    After successful execution, nodes will be updated to:

    ```shell
    {
        "127.0.0.1:1980": 1,
        "127.0.0.1:1981": 10
    }
    ```

4. Delete a node for the Upstream

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/upstreams/100 \
    -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PATCH -i -d '
    {
        "nodes": {
            "127.0.0.1:1980": null
        }
    }'
    ```

    ```
    HTTP/1.1 200 OK
    ...
    ```

    After successful execution, nodes will be updated to:

    ```shell
    {
        "127.0.0.1:1981": 10
    }
    ```

5. Replace the nodes of the Upstream

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/upstreams/100/nodes \
    -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PATCH -i -d '
    {
        "127.0.0.1:1982": 1
    }'
    ```

    ```
    HTTP/1.1 200 OK
    ...
    ```

    After the execution is successful, nodes will not retain the original data, and the entire update is:

    ```shell
    {
        "127.0.0.1:1982": 1
    }
    ```

#### Proxy client request to `https` Upstream service

1. Create a route and configure the upstream scheme as `https`.

    ```shell
    curl -i http://127.0.0.1:9180/apisix/admin/routes/1 \
    -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
    curl http://127.0.0.1:9080/get
    ```

    ```shell
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

:::note

Each node can be configured with a priority. A node with low priority will only be
used when all the nodes with higher priority have been tried or are unavailable.

:::

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

## SSL

### SSL API

SSL resource request address: /apisix/admin/ssls/{id}

### Request Methods

| Method | Request URI            | Request Body | Description                                     |
| ------ | ---------------------- | ------------ | ----------------------------------------------- |
| GET    | /apisix/admin/ssls      | NULL         | Fetches a list of all configured SSL resources. |
| GET    | /apisix/admin/ssls/{id} | NULL         | Fetch specified resource by id.                 |
| PUT    | /apisix/admin/ssls/{id} | {...}        | Creates a resource with the specified id.           |
| POST   | /apisix/admin/ssls      | {...}        | Creates a resource and assigns a random id.           |
| DELETE | /apisix/admin/ssls/{id} | NULL         | Removes the resource with the specified id.     |

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
| type         | False    | Auxiliary            | Identifies the type of certificate, default  `server`.                                                                             | `client` Indicates that the certificate is a client certificate, which is used when APISIX accesses the upstream; `server` Indicates that the certificate is a server-side certificate, which is used by APISIX when verifying client requests.     |
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

Sets Plugins which run globally. i.e these Plugins will be run before any Route/Service level Plugins.

### Global Rule API

Global Rule resource request address: /apisix/admin/global_rules/{id}

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
| plugins     | True     | Plugins that are executed during the request/response cycle. See [Plugin](terminology/plugin.md) for more. |            |
| create_time | False    | Epoch timestamp (in seconds) of the created time. If missing, this field will be populated automatically.             | 1602883670 |
| update_time | False    | Epoch timestamp (in seconds) of the updated time. If missing, this field will be populated automatically.             | 1602883670 |

## Consumer group

Group of Plugins which can be reused across Consumers.

### Consumer group API

Consumer group resource request address: /apisix/admin/consumer_groups/{id}

### Request Methods

| Method | Request URI                              | Request Body | Description                                                                                                                           |
| ------ | ---------------------------------------- | ------------ | ------------------------------------------------------------------------------------------------------------------------------------- |
| GET    | /apisix/admin/consumer_groups             | NULL         | Fetches a list of all Consumer groups.                                                                                                 |
| GET    | /apisix/admin/consumer_groups/{id}        | NULL         | Fetches specified Consumer group by id.                                                                                                |
| PUT    | /apisix/admin/consumer_groups/{id}        | {...}        | Creates a new Consumer group with the specified id.                                                                                    |
| DELETE | /apisix/admin/consumer_groups/{id}        | NULL         | Removes the Consumer group with the specified id.                                                                                      |
| PATCH  | /apisix/admin/consumer_groups/{id}        | {...}        | Updates the selected attributes of the specified, existing Consumer group. To delete an attribute, set value of attribute set to null. |
| PATCH  | /apisix/admin/consumer_groups/{id}/{path} | {...}        | Updates the attribute specified in the path. The values of other attributes remain unchanged.                                         |

### Request Body Parameters

| Parameter   | Required | Description                                                                                                        | Example                                          |
| ----------- | -------- | ------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------ |
| plugins     | True     | Plugins that are executed during the request/response cycle. See [Plugin](terminology/plugin.md) for more. |                                                  |
| desc        | False    | Description of usage scenarios.                                                                                    | customer xxxx                                    |
| labels      | False    | Attributes of the Consumer group specified as key-value pairs.                                                      | {"version":"v2","build":"16","env":"production"} |
| create_time | False    | Epoch timestamp (in seconds) of the created time. If missing, this field will be populated automatically.             | 1602883670                                       |
| update_time | False    | Epoch timestamp (in seconds) of the updated time. If missing, this field will be populated automatically.             | 1602883670                                       |

## Plugin config

Group of Plugins which can be reused across Routes.

### Plugin Config API

Plugin Config resource request address: /apisix/admin/plugin_configs/{id}

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
| plugins     | True     | Plugins that are executed during the request/response cycle. See [Plugin](terminology/plugin.md) for more. |                                                  |
| desc        | False    | Description of usage scenarios.                                                                                    | customer xxxx                                    |
| labels      | False    | Attributes of the Plugin config specified as key-value pairs.                                                      | {"version":"v2","build":"16","env":"production"} |
| create_time | False    | Epoch timestamp (in seconds) of the created time. If missing, this field will be populated automatically.             | 1602883670                                       |
| update_time | False    | Epoch timestamp (in seconds) of the updated time. If missing, this field will be populated automatically.             | 1602883670                                       |

## Plugin Metadata

### Plugin Metadata API

Plugin Metadata resource request address: /apisix/admin/plugin_metadata/{plugin_name}

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
curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/example-plugin  \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -i -X PUT -d '
{
    "skey": "val",
    "ikey": 1
}'
```

```shell
HTTP/1.1 201 Created
Date: Thu, 26 Dec 2019 04:19:34 GMT
Content-Type: text/plain
```

## Plugin

### Plugin API

Plugin resource request address: /apisix/admin/plugins/{plugin_name}

### Request Methods

| Method | Request URI                         | Request Body | Description                                    |
| ------ | ----------------------------------- | ------------ | ---------------------------------------------- |
| GET    | /apisix/admin/plugins/list          | NULL         | Fetches a list of all Plugins.                 |
| GET    | /apisix/admin/plugins/{plugin_name} | NULL         | Fetches the specified Plugin by `plugin_name`. |

### Request Body Parameters

The Plugin ({plugin_name}) of the data structure.

### Example API usage:

```shell
curl "http://127.0.0.1:9180/apisix/admin/plugins/list" \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1'

```shell
["zipkin","request-id",...]
```

```shell
curl "http://127.0.0.1:9180/apisix/admin/plugins/key-auth" -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1'
```

```json
{"$comment":"this is a mark for our injected plugin schema","properties":{"header":{"default":"apikey","type":"string"},"hide_credentials":{"default":false,"type":"boolean"},"_meta":{"properties":{"filter":{"type":"array","description":"filter determines whether the plugin needs to be executed at runtime"},"disable":{"type":"boolean"},"error_response":{"oneOf":[{"type":"string"},{"type":"object"}]},"priority":{"type":"integer","description":"priority of plugins by customized order"}},"type":"object"},"query":{"default":"apikey","type":"string"}},"type":"object"}
```

:::tip

You can use the `/apisix/admin/plugins?all=true` API to get all properties of all plugins.

Each Plugin has the attributes `name`, `priority`, `type`, `schema`, `consumer_schema` and `version`.

Defaults to only HTTP Plugins. If you need to get attributes from stream Plugins, use `/apisix/admin/plugins?all=true&subsystem=stream`.

:::

### Request Methods

| Method | Request URI                    | Request Body | Description                              |
| ------ | ------------------------------ | ------------ | ---------------------------------------- |
| GET    | /apisix/admin/plugins?all=true | NULL         | Fetches all attributes from all Plugins. |

### Request Arguments

| Name      | Description                   | Default |
| --------- | ----------------------------- | ------- |
| subsystem | The subsystem of the Plugins. | http    |

## Stream Route

Route used in the [Stream Proxy](./stream-proxy.md).

### Stream Route API

Stream Route resource request address:  /apisix/admin/stream_routes/{id}

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
| upstream    | False    | Upstream | Configuration of the [Upstream](./terminology/upstream.md). |                               |
| upstream_id | False    | Upstream | Id of the [Upstream](terminology/upstream.md) service.      |                               |
| remote_addr | False    | IP/CIDR  | Filters Upstream forwards by matching with client IP.               | "127.0.0.1/32" or "127.0.0.1" |
| server_addr | False    | IP/CIDR  | Filters Upstream forwards by matching with APISIX Server IP.        | "127.0.0.1/32" or "127.0.0.1" |
| server_port | False    | Integer  | Filters Upstream forwards by matching with APISIX Server port.      | 9090                          |
| sni         | False    | Host     | Server Name Indication.                                             | "test.com"                    |
| protocol.name | False    | String | Name of the protocol proxyed by xRPC framework.                     | "redis"                    |
| protocol.conf | False    | Configuration | Protocol-specific configuration.                             |                    |

To learn more about filtering in stream proxies, check [this](./stream-proxy.md#more-route-match-options) document.

## kms

kms means `Secrets Management`, which could use any secret manager supported, e.g. `vault`.

### kms API

kms resource request address: /apisix/admin/kms/{secretmanager}/{id}

### Request Methods

| Method | Request URI                        | Request Body | Description                                       |
| ------ | ---------------------------------- | ------------ | ------------------------------------------------- |
| GET    | /apisix/admin/secrets            | NULL         | Fetches a list of all secrets.                  |
| GET    | /apisix/admin/secrets/{manager}/{id} | NULL         | Fetches specified secrets by id.           |
| PUT    | /apisix/admin/secrets/{manager}            | {...}        | Create new secrets configuration.                              |
| DELETE | /apisix/admin/secrets/{manager}/{id} | NULL         | Removes the secrets with the specified id. |
| PATCH  | /apisix/admin/secrets/{manager}/{id}        | {...}        | Updates the selected attributes of the specified, existing secrets. To delete an attribute, set value of attribute set to null. |
| PATCH  | /apisix/admin/secrets/{manager}/{id}/{path} | {...}        | Updates the attribute specified in the path. The values of other attributes remain unchanged.                                 |

### Request Body Parameters

When `{secretmanager}` is `vault`:

| Parameter   | Required | Type        | Description                                                                                                        | Example                                          |
| ----------- | -------- | ----------- | ------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------ |
| uri    | True     | URI        | URI of the vault server.                                                                                              |                                                  |
| prefix    | True    | string        | key prefix
| token     | True    | string      | vault token. |                                                  |

Example Configuration:

```shell
{
    "uri": "https://localhost/vault",
    "prefix": "/apisix/kv",
    "token": "343effad"
}
```

Example API usage:

```shell
curl -i http://127.0.0.1:9180/apisix/admin/kms/vault/test2 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "http://xxx/get",
    "prefix" : "apisix",
    "token" : "apisix"
}'
```

```shell
HTTP/1.1 200 OK
...

{"key":"\/apisix\/secrets\/vault\/test2","value":{"id":"vault\/test2","token":"apisix","prefix":"apisix","update_time":1669625828,"create_time":1669625828,"uri":"http:\/\/xxx\/get"}}
```

### Response Parameters

Currently, the response is returned from etcd.
