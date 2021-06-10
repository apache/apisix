---
title: limit-req
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

## Summary

  - [Introduction](#introduction)
  - [Attributes](#attributes)
  - [Example](#example)
    - [How to enable on the `route` or `serivce`](#how-to-enable-on-the-route-or-serivce)
    - [How to enable on the `consumer`](#how-to-enable-on-the-consumer)
  - [Disable Plugin](#disable-plugin)

## Introduction

limit request rate using the "leaky bucket" method.

## Attributes

| Name          | Type    | Requirement | Default | Valid                                                                    | Description                                                                                                                                                               |
| ------------- | ------- | ----------- | ------- | ------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| rate          | integer | required    |         | rate > 0                                                                 | the specified request rate (number per second) threshold. Requests exceeding this rate (and below `burst`) will get delayed to conform to the rate.                       |
| burst         | integer | required    |         | burst >= 0                                                               | the number of excessive requests per second allowed to be delayed. Requests exceeding this hard limit will get rejected immediately.                                      |
| key           | string  | required    |         | ["remote_addr", "server_addr", "http_x_real_ip", "http_x_forwarded_for", "consumer_name"] | the user specified key to limit the rate, now accept those as key: "remote_addr"(client's IP), "server_addr"(server's IP), "X-Forwarded-For/X-Real-IP" in request header, "consumer_name"(consumer's username). |
| rejected_code | integer | optional    | 503     | [200,...,599]                                                            | The HTTP status code returned when the request exceeds the threshold is rejected.                                                                      |
| nodelay       | boolean | optional    | false   |                                                                          | If nodelay flag is true, bursted requests will not get delayed  |

**Key can be customized by the user, only need to modify a line of code of the plug-in to complete.  It is a security consideration that is not open in the plugin.**

## Example

### How to enable on the `route` or `serivce`

Take `route` as an example (the use of `service` is the same method), enable the `limit-req` plugin on the specified route.

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/index.html",
    "plugins": {
        "limit-req": {
            "rate": 1,
            "burst": 2,
            "rejected_code": 503,
            "key": "remote_addr"
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "39.97.63.215:80": 1
        }
    }
}'
```

You can open dashboard with a browser: `http://127.0.0.1:9080/apisix/dashboard/`, to complete the above operation through the web interface, first add a route:

![add route](../../../assets/images/plugin/limit-req-1.png)

Then add limit-req plugin:

![add plugin](../../../assets/images/plugin/limit-req-2.png)

**Test Plugin**

The above configuration limits the request rate to 1 per second. If it is greater than 1 and less than 3, the delay will be added. If the rate exceeds 3, it will be rejected:

```shell
curl -i http://127.0.0.1:9080/index.html
```

When you exceed, you will receive a response header with a 503 return code:

```html
HTTP/1.1 503 Service Temporarily Unavailable
Content-Type: text/html
Content-Length: 194
Connection: keep-alive
Server: APISIX web server

<html>
<head><title>503 Service Temporarily Unavailable</title></head>
<body>
<center><h1>503 Service Temporarily Unavailable</h1></center>
<hr><center>openresty</center>
</body>
</html>
```

This means that the limit req plugin is in effect.

### How to enable on the `consumer`

To enable the `limit-req` plugin on the consumer, it needs to be used together with the authorization plugin. Here, the key-auth authorization plugin is taken as an example.

1. Bind the `limit-req` plugin to the consumer

```shell
curl http://127.0.0.1:9080/apisix/admin/consumers -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "username": "consumer_jack",
    "plugins": {
        "key-auth": {
            "key": "auth-jack"
        },
        "limit-req": {
            "rate": 1,
            "burst": 1,
            "rejected_code": 403,
            "key": "consumer_name"
        }
    }
}'
```

2. Create a `route` and enable the `key-auth` plugin

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/index.html",
    "plugins": {
        "key-auth": {
            "key": "auth-jack"
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

**Test Plugin**

The value of `rate + burst` is not exceeded.

```shell
curl -i http://127.0.0.1:9080/index.html -H 'apikey: auth-jack'
HTTP/1.1 200 OK
......
```

When the value of `rate + burst` is exceeded.

```shell
curl -i http://127.0.0.1:9080/index.html -H 'apikey: auth-jack'
HTTP/1.1 403 Forbidden
.....
<html>
<head><title>403 Forbidden</title></head>
<body>
<center><h1>403 Forbidden</h1></center>
<hr><center>openresty</center>
</body>
</html>
```

Explains that the `limit-req` plugin tied to `consumer` has taken effect.

## Disable Plugin

When you want to disable the limit req plugin, it is very simple,
 you can delete the corresponding json configuration in the plugin configuration,
  no need to restart the service, it will take effect immediately:

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/index.html",
    "id": 1,
    "plugins": {
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "39.97.63.215:80": 1
        }
    }
}'
```

Remove the `limit-req` plugin on `consumer`.

```shell
curl http://127.0.0.1:9080/apisix/admin/consumers -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "username": "consumer_jack",
    "plugins": {
        "key-auth": {
            "key": "auth-jack"
        }
    }
}'
```

The limit req plugin has been disabled now. It works for other plugins.
