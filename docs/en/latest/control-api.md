---
title: Control API
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

The control API can be used to

* expose APISIX internal state
* control the behavior of a single isolate APISIX data panel

By default, the control API server is enabled and listens to `127.0.0.1:9090`. You can change it via
the `control` section under `apisix` in `conf/config.yaml`:

```yaml
apisix:
  ...
  enable_control: true
  control:
    ip: "127.0.0.1"
    port: 9090
```

The control API server does not support parameter matching by default, if you want to enable parameter matching in plugin's control API
you can add `router: 'radixtree_uri_with_parameter'` to the `control` section.

Note that the control API server should not be configured to listen to the public traffic!

## Control API Added via plugin

Plugin can add its control API when it is enabled.
Some plugins in APISIX have added their own control APIs. If you are interested in these APIs,
please refer to their documentation.

## Plugin independent Control API

Here is the supported API:

### GET /v1/schema

Introduced since `v2.2`.

Return the jsonschema used by this APISIX instance in the format below:

```json
{
    "main": {
        "route": {
            "properties": {...}
        },
        "upstream": {
            "properties": {...}
        },
        ...
    },
    "plugins": {
        "example-plugin": {
            "consumer_schema": {...},
            "metadata_schema": {...},
            "schema": {...},
            "type": ...,
            "priority": 0,
            "version": 0.1
        },
        ...
    },
    "stream-plugins": {
        "mqtt-proxy": {
            ...
        },
        ...
    }
}
```

For `plugins` part, only enabled plugins will be returned. Some plugins may lack
of fields like `consumer_schema` or `type`, it is depended on by the plugin's
definition.

### GET /v1/healthcheck

Introduced since `v2.3`.

Return current [health check](health-check.md) status in the format below:

```json
[
    {
        "healthy_nodes": [
            {
                "host": "127.0.0.1",
                "port": 1980,
                "priority": 0,
                "weight": 1
            }
        ],
        "name": "upstream#/upstreams/1",
        "nodes": [
            {
                "host": "127.0.0.1",
                "port": 1980,
                "priority": 0,
                "weight": 1
            },
            {
                "host": "127.0.0.2",
                "port": 1988,
                "priority": 0,
                "weight": 1
            }
        ],
        "src_id": "1",
        "src_type": "upstreams"
    },
    {
        "healthy_nodes": [
            {
                "host": "127.0.0.1",
                "port": 1980,
                "priority": 0,
                "weight": 1
            }
        ],
        "name": "upstream#/routes/1",
        "nodes": [
            {
                "host": "127.0.0.1",
                "port": 1980,
                "priority": 0,
                "weight": 1
            },
            {
                "host": "127.0.0.1",
                "port": 1988,
                "priority": 0,
                "weight": 1
            }
        ],
        "src_id": "1",
        "src_type": "routes"
    }
]
```

Each entry contains fields below:

* src_type: where the health checker comes from. The value is one of `["routes", "services", "upstreams"]`.
* src_id: the id of object which creates the health checker. For example, if Upstream
object with id 1 creates a health checker, the `src_type` is `upstreams` and the `src_id` is `1`.
* name: the name of the health checker.
* nodes: the target nodes of the health checker.
* healthy_nodes: the healthy node known by the health checker.

User can also use `/v1/healthcheck/$src_type/$src_id` can get the status of a health checker.

For example, `GET /v1/healthcheck/upstreams/1` returns:

```json
{
    "healthy_nodes": [
        {
            "host": "127.0.0.1",
            "port": 1980,
            "priority": 0,
            "weight": 1
        }
    ],
    "name": "upstream#/upstreams/1",
    "nodes": [
        {
            "host": "127.0.0.1",
            "port": 1980,
            "priority": 0,
            "weight": 1
        },
        {
            "host": "127.0.0.2",
            "port": 1988,
            "priority": 0,
            "weight": 1
        }
    ],
    "src_id": "1",
    "src_type": "upstreams"
}
```

### POST /v1/gc

Introduced since `v2.8`.

Trigger a full GC in the http subsystem.
Note that when you enable stream proxy, APISIX will run another Lua VM for the stream subsystem. It won't trigger a full GC in this Lua VM .

### Get /v1/routes

Introduced since `v3.0`.

Return all routes info in the format below:

```json
[
  {
    "update_count": 0,
    "value": {
      "priority": 0,
      "uris": [
        "/hello"
      ],
      "id": "1",
      "upstream": {
        "scheme": "http",
        "pass_host": "pass",
        "nodes": [
          {
            "port": 1980,
            "host": "127.0.0.1",
            "weight": 1
          }
        ],
        "type": "roundrobin",
        "hash_on": "vars"
      },
      "status": 1
    },
    "clean_handlers": {},
    "has_domain": false,
    "orig_modifiedIndex": 1631193445,
    "modifiedIndex": 1631193445,
    "key": "/routes/1"
  }
]
```

### Get /v1/route/{route_id}

Introduced since `v3.0`.

Return specific route info with **route_id** in the format below:

```json
{
  "update_count": 0,
  "value": {
    "priority": 0,
    "uris": [
      "/hello"
    ],
    "id": "1",
    "upstream": {
      "scheme": "http",
      "pass_host": "pass",
      "nodes": [
        {
          "port": 1980,
          "host": "127.0.0.1",
          "weight": 1
        }
      ],
      "type": "roundrobin",
      "hash_on": "vars"
    },
    "status": 1
  },
  "clean_handlers": {},
  "has_domain": false,
  "orig_modifiedIndex": 1631193445,
  "modifiedIndex": 1631193445,
  "key": "/routes/1"
}
```

### Get /v1/services

Introduced since `v2.11`.

Return all services info in the format below:

```json
[
  {
    "has_domain": false,
    "clean_handlers": {},
    "modifiedIndex": 671,
    "key": "/apisix/services/200",
    "createdIndex": 671,
    "value": {
      "upstream": {
          "scheme": "http",
          "hash_on": "vars",
          "pass_host": "pass",
          "type": "roundrobin",
          "nodes": [
            {
              "port": 1980,
              "weight": 1,
              "host": "127.0.0.1"
            }
          ]
      },
      "create_time": 1634552648,
      "id": "200",
      "plugins": {
        "limit-count": {
          "key": "remote_addr",
          "time_window": 60,
          "redis_timeout": 1000,
          "allow_degradation": false,
          "show_limit_quota_header": true,
          "policy": "local",
          "count": 2,
          "rejected_code": 503
        }
      },
      "update_time": 1634552648
    }
  }
]
```

### Get /v1/service/{service_id}

Introduced since `v2.11`.

Return specific service info with **service_id** in the format below:

```json
{
  "has_domain": false,
  "clean_handlers": {},
  "modifiedIndex": 728,
  "key": "/apisix/services/5",
  "createdIndex": 728,
  "value": {
    "create_time": 1634554563,
    "id": "5",
    "upstream": {
      "scheme": "http",
      "hash_on": "vars",
      "pass_host": "pass",
      "type": "roundrobin",
      "nodes": [
        {
          "port": 1980,
          "weight": 1,
          "host": "127.0.0.1"
        }
      ]
    },
    "update_time": 1634554563
  }
}
```

### Get /v1/upstreams

Introduced since `v2.11.0`.

Dump all upstreams in the format below:

```json
[
   {
      "value":{
         "scheme":"http",
         "pass_host":"pass",
         "nodes":[
            {
               "host":"127.0.0.1",
               "port":80,
               "weight":1
            },
            {
               "host":"foo.com",
               "port":80,
               "weight":2
            }
         ],
         "hash_on":"vars",
         "update_time":1634543819,
         "key":"remote_addr",
         "create_time":1634539759,
         "id":"1",
         "type":"chash"
      },
      "has_domain":true,
      "key":"\/apisix\/upstreams\/1",
      "clean_handlers":{
      },
      "createdIndex":938,
      "modifiedIndex":1225
   }
]
```

### Get /v1/upstream/{upstream_id}

Introduced since `v2.11.0`.

Dump specific upstream info with **upstream_id** in the format below:

```json
{
   "value":{
      "scheme":"http",
      "pass_host":"pass",
      "nodes":[
         {
            "host":"127.0.0.1",
            "port":80,
            "weight":1
         },
         {
            "host":"foo.com",
            "port":80,
            "weight":2
         }
      ],
      "hash_on":"vars",
      "update_time":1634543819,
      "key":"remote_addr",
      "create_time":1634539759,
      "id":"1",
      "type":"chash"
   },
   "has_domain":true,
   "key":"\/apisix\/upstreams\/1",
   "clean_handlers":{
   },
   "createdIndex":938,
   "modifiedIndex":1225
}
```
