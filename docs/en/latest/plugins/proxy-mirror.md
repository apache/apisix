---
title: proxy-mirror
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

The proxy-mirror plugin, which provides the ability to mirror client requests.

*Note*: The response returned by the mirror request is ignored.

## Attributes

| Name | Type   | Requirement | Default | Valid | Description                                                                                                                 |
| ---- | ------ | ----------- | ------- | ----- | --------------------------------------------------------------------------------------------------------------------------- |
| host | string | required    |         |       | Specify a mirror service address, e.g. http://127.0.0.1:9797 (address needs to contain scheme: http or https, and without the path part) |
| path | string | optional    |         |       | Specify the mirror request's path part. Without it the current path will be used. |
| sample_ratio | number | optional    | 1       |  [0.00001, 1]     | the sample ratio that requests will be mirrored. |

### Examples

#### Enable the plugin

example 1:  enable the proxy-mirror plugin for a specific route :

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "plugins": {
        "proxy-mirror": {
           "host": "http://127.0.0.1:9797"
        }
    },
    "upstream": {
        "nodes": {
            "127.0.0.1:1999": 1
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
Content-Type: application/octet-stream
Content-Length: 12
Connection: keep-alive
Server: APISIX web server
Date: Wed, 18 Mar 2020 13:01:11 GMT
Last-Modified: Thu, 20 Feb 2020 14:21:41 GMT

hello world
```

> Since the specified mirror address is 127.0.0.1:9797, so to verify whether this plugin is in effect, we need to confirm on the service with port 9797.
> For example, we can start a simple server:  python -m SimpleHTTPServer 9797

#### Disable Plugin

Remove the corresponding JSON in the plugin configuration to disable the plugin immediately without restarting the service:

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/hello",
    "plugins": {},
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1999": 1
        }
    }
}'
```

The plugin has been disabled now.

## Customize proxy timeouts for mirrored sub-request

We can customize proxy timeouts for the mirrored sub-request in the `plugin_attr` of `conf/config.yaml`. This is useful while mirroring traffic to a slow backend in a long connection scenario.

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| connect | string | 60s | connect timeout to the mirrored upstream |
| read | string | 60s | read timeout to the mirrored upstream |
| send | string | 60s | send timeout to the mirrored upstream |

```yaml
plugin_attr:
  proxy-mirror:
    timeout:
      connect: 2000ms
      read: 2000ms
      send: 2000ms
```
