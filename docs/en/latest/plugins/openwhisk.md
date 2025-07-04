---
title: openwhisk
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - OpenWhisk
description: This document contains information about the Apache openwhisk Plugin.
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

The `openwhisk` Plugin is used to integrate APISIX with [Apache OpenWhisk](https://openwhisk.apache.org) serverless platform.

This Plugin can be configured on a Route and requests will be send to the configured OpenWhisk API endpoint as the upstream.

## Attributes

| Name              | Type    | Required | Default | Valid values | Description                                                                                                |
| ----------------- | ------- | -------- | ------- | ------------ | ---------------------------------------------------------------------------------------------------------- |
| api_host          | string  | True     |         |              | OpenWhisk API host address. For example, `https://localhost:3233`.                                         |
| ssl_verify        | boolean | False    | true    |              | When set to `true` verifies the SSL certificate.                                                           |
| service_token     | string  | True     |         |              | OpenWhisk service token. The format is `xxx:xxx` and it is passed through basic auth when calling the API. |
| namespace         | string  | True     |         |              | OpenWhisk namespace. For example `guest`.                                                                  |
| action            | string  | True     |         |              | OpenWhisk action. For example `hello`.                                                                     |
| result            | boolean | False    | true    |              | When set to `true` gets the action metadata (executes the function and gets response).                     |
| timeout           | integer | False    | 60000ms | [1, 60000]ms | OpenWhisk action and HTTP call timeout in ms.                                                              |
| keepalive         | boolean | False    | true    |              | When set to `true` keeps the connection alive for reuse.                                                   |
| keepalive_timeout | integer | False    | 60000ms | [1000,...]ms | Time is ms for connection to remain idle without closing.                                                  |
| keepalive_pool    | integer | False    | 5       | [1,...]      | Maximum number of requests that can be sent on this connection before closing it.                          |

:::note

The `timeout` attribute sets the time taken by the OpenWhisk action to execute, and the timeout for the HTTP client in APISIX. OpenWhisk action calls may take time to pull the runtime image and start the container. So, if the value is set too small, it may cause a large number of requests to fail.

OpenWhisk supports timeouts in the range 1ms to 60000ms and it is recommended to set it to at least 1000ms.

:::

## Enable Plugin

Before configuring the Plugin, you need to have OpenWhisk running. The example below shows OpenWhisk in standalone mode:

```shell
docker run --rm -d \
  -h openwhisk --name openwhisk \
  -p 3233:3233 -p 3232:3232 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  openwhisk/standalone:nightly
docker exec openwhisk waitready
```

Install the [openwhisk-cli](https://github.com/apache/openwhisk-cli) utility.

You can download the released executable binaries wsk for Linux systems from the [openwhisk-cli](https://github.com/apache/openwhisk-cli) repository.

You can then create an action to test:

```shell
wsk property set --apihost "http://localhost:3233" --auth "23bc46b1-71f6-4ed5-8c54-816aa4f8c502:123zO3xZCLrMN6v2BKK1dXYFpXlPkccOFqm12CdAsMgRU4VrNZ9lyGVCGuMDGIwP"
wsk action update test <(echo 'function main(){return {"ready":true}}') --kind nodejs:14
```

You can now configure the Plugin on a specific Route and point to this running OpenWhisk service:

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/hello",
    "plugins": {
        "openwhisk": {
            "api_host": "http://localhost:3233",
            "service_token": "23bc46b1-71f6-4ed5-8c54-816aa4f8c502:123zO3xZCLrMN6v2BKK1dXYFpXlPkccOFqm12CdAsMgRU4VrNZ9lyGVCGuMDGIwP",
            "namespace": "guest",
            "action": "test"
        }
    }
}'
```

## Example usage

Once you have configured the Plugin, you can send a request to the Route and it will invoke the configured action:

```shell
curl -i http://127.0.0.1:9080/hello
```

This will give back the response from the action:

```json
{ "ready": true }
```

## Delete Plugin

To remove the `openwhisk` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/index.html",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```
