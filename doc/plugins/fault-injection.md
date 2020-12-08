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

- [中文](../zh-cn/plugins/fault-injection.md)

## Name

Fault injection plugin, this plugin can be used with other plugins and will be executed before other plugins.  The `abort` attribute will directly return the user-specified http code to the client and terminate the subsequent plugins. The `delay` attribute will delay a request and execute subsequent plugins.

## Attributes

| Name              | Type    | Requirement | Default | Valid      | Description                                      |
| ----------------- | ------- | ----------- | ------- | ---------- | ------------------------------------------------ |
| abort.http_status | integer | required    |         | [200, ...] | user-specified http code returned to the client. |
| abort.body        | string  | optional    |         |            | response data returned to the client. Nginx varialbe can be used inside, like `client addr: $remote_addr\n`           |
| abort.percentage  | integer | optional    |         | [0, 100]   | percentage of requests to be aborted.            |
| delay.duration    | number  | required    |         |            | delay time (can be decimal).                     |
| delay.percentage  | integer | optional    |         | [0, 100]   | percentage of requests to be delayed.            |

Note: One of `abort` and `delay` must be specified.

## How To Enable

### Enable the plugin

1: enable the fault-injection plugin for a specific route and specify the abort attribute：

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "plugins": {
       "fault-injection": {
           "abort": {
              "http_status": 200,
              "body": "Fault Injection!"
           }
       }
    },
    "upstream": {
       "nodes": {
           "127.0.0.1:1980": 1
       },
       "type": "roundrobin"
    },
    "uri": "/hello"
}'
```

Test plugin：

```shell
$ curl http://127.0.0.1:9080/hello -i
HTTP/1.1 200 OK
Date: Mon, 13 Jan 2020 13:50:04 GMT
Content-Type: text/plain
Transfer-Encoding: chunked
Connection: keep-alive
Server: APISIX web server

Fault Injection!
```

> http status is 200 and the response body is "Fault Injection! " indicate that the plugin is enabled.

2: Enable the `fault-injection` plugin for a specific route and specify the `delay` attribute:

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "plugins": {
       "fault-injection": {
           "delay": {
              "duration": 3
           }
       }
    },
    "upstream": {
       "nodes": {
           "127.0.0.1:1980": 1
       },
       "type": "roundrobin"
    },
    "uri": "/hello"
}'
```

Test plugin：

```shell
$ time curl http://127.0.0.1:9080/hello -i
HTTP/1.1 200 OK
Content-Type: application/octet-stream
Content-Length: 6
Connection: keep-alive
Server: APISIX web server
Date: Tue, 14 Jan 2020 14:30:54 GMT
Last-Modified: Sat, 11 Jan 2020 12:46:21 GMT

hello

real    0m3.034s
user    0m0.007s
sys     0m0.010s
```

## Disable Plugin

Remove the corresponding JSON in the plugin configuration to disable the plugin immediately without restarting the service:

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
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

The plugin has been disabled now.
