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

- [中文](../zh-cn/plugins/api-blocker.md)

# Summary

- [**Name**](#name)
- [**Attributes**](#attributes)
- [**How To Enable**](#how-to-enable)
- [**Test Plugin**](#test-plugin)
- [**Disable Plugin**](#disable-plugin)

## Name

The plugin implements API fuse functionality to help us protect our upstream business services.

## Attributes

| Name          | Type          | Requirement | Default | Valid      | Description                                                                 |
| ------------- | ------------- | ----------- | ------- | ---------- | --------------------------------------------------------------------------- |
| unhealthy_response_code           | integer | required |          | [200, ..., 600] | return error code when unhealthy |
| unhealthy.http_statuses | array[integer] | optional | {500}      | [500, ..., 599] | Status codes when unhealthy |
| unhealthy.failures      | integer        | optional | 1          | >=1             | Number of consecutive error requests that triggered an unhealthy state |
| healthy.http_statuses   | array[integer] | optional | {200, 206} | [200, ..., 499] | Status codes when healthy |
| successes.successes     | integer        | optional | 1          | >=1             | Number of consecutive normal requests that trigger health status |

## How To Enable

Here's an example, enable the `api-breaker` plugin on the specified route:

```shell
curl "http://127.0.0.1:9080/apisix/admin/routes/5" -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
   {
      "plugins": {
          "api-breaker": {
              "unhealthy_response_code": 502,
              "unhealthy": {
                  "http_statuses": [500, 503],
                  "failures": 3
              },
              "healthy": {
                  "http_statuses": [200],
                  "successes": 1
              }
          }
      },
      "uri": "/get",
      "host": "127.0.0.1",
      "upstream_id": 50
  }'
```

## Test Plugin

```shell
$ curl -i -X POST "http://127.0.0.1:9080/get?list=1,b,c"
HTTP/1.1 200 OK
Content-Type: application/octet-stream
Content-Length: 0
Connection: keep-alive
Server: APISIX/1.5
Server: openresty/1.17.8.2
Date: Tue, 29 Sep 2020 05:00:02 GMT

... ...
```

> Then. Like the configuration above, if your upstream service returns 500. 3 times in a row. The client will receive a 502 (unhealthy_response_code) response.



## Disable Plugin

When you want to disable the `api-breader` plugin, it is very simple, you can delete the corresponding json configuration in the plugin configuration, no need to restart the service, it will take effect immediately:

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/*",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```

The `api-breaker` plugin has been disabled now. It works for other plugins.
