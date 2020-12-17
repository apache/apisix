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

- [中文](../zh-cn/plugins/node-status.md)

# Summary

- [**Name**](#name)
- [**Attributes**](#attributes)
- [**API**](#api)
- [**How To Enable**](#how-to-enable)
- [**Test Plugin**](#test-plugin)
- [**Disable Plugin**](#disable-plugin)

## Name

`node-status` is a plugin which we could get request status information through it's API.

## Attributes

None

## API

This plugin will add `/apisix/status` to get status information.
You may need to use [interceptors](../plugin-interceptors.md) to protect it.

## How To Enable

1. Configure `node-status` in the plugin list of the configuration file `conf/config.yaml`,
then you can add this plugin in any route.

```
plugins:                          # plugin list
  - example-plugin
  - limit-req
  - node-status
  - jwt-auth
  - zipkin
  ......
```

After starting `APISIX`, you can get status information through the API `/apisix/status`.

2. Create a route object, and enable plugin `node-status`.

```sh
$ curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -i -d '
{
    "uri": "/route1",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "192.168.1.100:80:": 1
        }
    },
    "plugins": {
        "node-status":{}
    }
}'
```

You have to configure `node-status` in the configuration file `apisix/conf/config.yaml` before creating a route like this.
And this plugin will not make any difference in future requests, so usually we don't set this plugin when creating routes.

## Test Plugin

1. Request with uri `/apisix/status`

```sh
$ curl localhost:9080/apisix/status -i
HTTP/1.1 200 OK
Date: Tue, 03 Nov 2020 11:12:55 GMT
Content-Type: text/plain; charset=utf-8
Transfer-Encoding: chunked
Connection: keep-alive
Server: APISIX web server

{"status":{"total":"23","waiting":"0","accepted":"22","writing":"1","handled":"22","active":"1","reading":"0"},"id":"6790a064-8f61-44ba-a6d3-5df42f2b1bb3"}
```

2. Parameter Description

| Parameter    | Description                                        |
| ------------ | -------------------------------------------- |
| status       | status information                                     |
| total        | the total number of client requests                               |
| waiting      | the current number of idle client connections waiting for a request               |
| accepted     | the total number of accepted client connections                         |
| writing      | the current number of connections where APISIX is writing the response back to the client               |
| handled      | the total number of handled connections. Generally, the parameter value is the same as accepted unless some resource limits have been reached          |
| active       | the current number of active client connections including waiting connections                       |
| reading      | the current number of connections where APISIX is reading the request header                   |
| id           | APISIX's uid which is saved in apisix/conf/apisix.uid  |

## Disable Plugin

1. You can delete `node-status` in the plugin list of the configuration file `apisix/conf/config.yaml`,
then you can not add this plugin in any route.

```
plugins:                          # plugin list
  - example-plugin
  - limit-req
  - jwt-auth
  - zipkin
  ......
```

2. When you want to disable the `node-status` plugin in the route, it is very simple,
you can delete the corresponding json configuration in the plugin configuration,
no need to restart the service, it will take effect immediately.

```sh
$ curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -i -d '
{
    "uri": "/route1",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "192.168.1.100:80": 1
        }
    },
    "plugins": {}
}'
```
