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

# Summary
- [**Name**](#name)
- [**Attributes**](#attributes)
- [**How To Enable**](#how-to-enable)
- [**Test Plugin**](#test-plugin)
- [**Disable Plugin**](#disable-plugin)


## Name

`udp-logger` is a plugin which push Log data requests to UDP servers.

This will provide the ability to send Log data requests as JSON objects to Monitoring tools and other UDP servers.

## Attributes

|Name          |Requirement  |Description|
|---------     |--------|-----------|
| host |required| IP address or the Hostname of the UDP server.|
| port |required| Target upstream port.|
| timeout |optional|Timeout for the upstream to send data.|

## How To Enable

1. Here is an examle on how to enable udp-logger plugin for a specific route.

```shell
curl http://127.0.0.1:9080/apisix/admin/consumers -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "username": "foo",
    "plugins": {
          "plugins": {
                "udp-logger": {
                     "host": "127.0.0.1",
                     "port": 3000
                }
           },
          "upstream": {
               "type": "roundrobin",
               "nodes": {
                   "127.0.0.1:1980": 1
               }
          },
          "uri": "/hello"
    }
}'
```

## Test Plugin

* success:

```shell
$ curl -i http://127.0.0.1:9080/hello
HTTP/1.1 200 OK
...
hello, world
```

## Disable Plugin

When you want to disable the `udp-logger` plugin, it is very simple,
 you can delete the corresponding json configuration in the plugin configuration,
  no need to restart the service, it will take effect immediately:

```shell
$ curl http://127.0.0.1:2379/apisix/admin/routes/1 -X PUT -d value='
{
    "methods": ["GET"],
    "uri": "/hello",
    "plugins": {},
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```
