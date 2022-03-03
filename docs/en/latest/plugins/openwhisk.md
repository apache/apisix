---
title: openwhisk
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

The `openwhisk` plugin is used to support integration with the [Apache OpenWhisk](https://openwhisk.apache.org) serverless platform and can be set up on a route in place of Upstream, which will take over the request and send it to the OpenWhisk API endpoint.

Users can call the OpenWhisk action via APISIX, pass the request parameters via JSON and get the response content.

## Attributes

| Name | Type | Requirement | Default | Valid | Description |
| -- | -- | -- | -- | -- | -- |
| api_host | string | required |   |   | OpenWhisk API host (eg. https://localhost:3233) |
| ssl_verify | boolean | optional | true |   | Whether to verify the certificate |
| service_token | string | required |   |   | OpenWhisk ServiceToken (The format is `xxx:xxx`，Passed through Basic Auth when calling the API) |
| namespace | string | required |   |   | OpenWhisk  Namespace (eg. guest) |
| action | string | required |   |   | OpenWhisk Action (eg. hello) |
| result | boolean | optional | true |   | Whether to get Action metadata (default to execute function and get response; false to get Action metadata but not execute Action, including runtime, function body, restrictions, etc.) |
| timeout | integer | optional | 60000ms | [1, 60000]ms | OpenWhisk Action and HTTP call timeout. |
| keepalive | boolean | optional | true |   | HTTP keepalive |
| keepalive_timeout | integer | optional | 60000ms | [1000,...] | keepalive idle timeout |
| keepalive_pool | integer | optional | 5 | [1,...] | Connection pool limit |

:::note

- The `timeout` property controls both the time taken by the OpenWhisk Action to execute and the timeout of the HTTP client in APISIX. OpenWhisk Action calls may consume time on pulling the runtime image and starting the container, so if you set the value too small, you may cause a large number of requests to fail. OpenWhisk supports timeouts ranging from 1ms to 60000ms, and we recommended to set at least 1000ms or more.

:::

## Example

First, you need to run the OpenWhisk environment. Here is an example of using OpenWhisk standalone mode.

```shell
docker run --rm -d \
  -h openwhisk --name openwhisk \
  -p 3233:3233 -p 3232:3232 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  openwhisk/standalone:nightly
docker exec openwhisk waitready
```

Then, you need to create an Action for testing.

```shell
wsk property set --apihost "http://localhost:3233" --auth "23bc46b1-71f6-4ed5-8c54-816aa4f8c502:123zO3xZCLrMN6v2BKK1dXYFpXlPkccOFqm12CdAsMgRU4VrNZ9lyGVCGuMDGIwP"
wsk action update test <(echo 'function main(){return {"ready":true}}') --kind nodejs:14
```

Here is an example of creating a Route and enabling this plugin

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

Finally, you can send a request to this route and you will get the following response. And you can disable it by removing the openwhsik plugin from the route.

```json
{"ready": true}
```
