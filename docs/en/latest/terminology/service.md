---
title: Service
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

A Service is an abstraction of an API (which can also be understood as a set of [Route](./route.md) abstractions). It usually corresponds to an upstream service abstraction.

The relationship between Routes and a Service is usually N:1 as shown in the image below.

![service-example](../../../assets/images/service-example.png)

As shown, different Routes could be bound to the same Service. This reduces redundancy as these bounded Routes will have the same [Upstream](./upstream.md) and [Plugin](./plugin.md) configurations.

For more information about Service, please refer to [Admin API Service object](../admin-api.md#service).

## Examples

The following example creates a Service that enables the `limit-count` Plugin and then binds it to the Routes with the ids `100` and `101`.

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

1. Create a Service.

```shell
curl http://127.0.0.1:9180/apisix/admin/services/200 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "plugins": {
        "limit-count": {
            "count": 2,
            "time_window": 60,
            "rejected_code": 503,
            "key": "remote_addr"
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```

2. create new Route and reference the service by id `200`

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/routes/100 \
    -H "X-API-KEY: $admin_key" -X PUT -d '
    {
        "methods": ["GET"],
        "uri": "/index.html",
        "service_id": "200"
    }'
    ```

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/routes/101 \
    -H "X-API-KEY: $admin_key" -X PUT -d '
    {
        "methods": ["GET"],
        "uri": "/foo/index.html",
        "service_id": "200"
    }'
    ```

We can also specify different Plugins or Upstream for the Routes than the ones defined in the Service. The example below creates a Route with a `limit-count` Plugin. This Route will continue to use the other configurations defined in the Service (here, the Upstream configuration).

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/routes/102 \
    -H "X-API-KEY: $admin_key" -X PUT -d '
    {
        "uri": "/bar/index.html",
        "id": "102",
        "service_id": "200",
        "plugins": {
            "limit-count": {
                "count": 2000,
                "time_window": 60,
                "rejected_code": 503,
                "key": "remote_addr"
            }
        }
    }'
    ```

:::note

When a Route and a Service enable the same Plugin, the one defined in the Route is given the higher priority.

:::
