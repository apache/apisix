---
title: fault-injection
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - Fault Injection
  - fault-injection
description: This document contains information about the Apache APISIX fault-injection Plugin.
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

The `fault-injection` Plugin can be used to test the resiliency of your application. This Plugin will be executed before the other configured Plugins.

The `abort` attribute will directly return the specified HTTP code to the client and skips executing the subsequent Plugins.

The `delay` attribute delays a request and executes the subsequent Plugins.

## Attributes

| Name              | Type    | Requirement | Default | Valid      | Description                                                                                                                                                 |
|-------------------|---------|-------------|---------|------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------|
| abort.http_status | integer | required    |         | [200, ...] | HTTP status code of the response to return to the client.                                                                                                   |
| abort.body        | string  | optional    |         |            | Body of the response returned to the client. Nginx variables like `client addr: $remote_addr\n` can be used in the body.                                    |
| abort.headers     | object  | optional    |         |            | Headers of the response returned to the client. The values in the header can contain Nginx variables like `$remote_addr`. |
| abort.percentage  | integer | optional    |         | [0, 100]   | Percentage of requests to be aborted.                                                                                                                       |
| abort.vars        | array[] | optional    |         |            | Rules which are matched before executing fault injection. See [lua-resty-expr](https://github.com/api7/lua-resty-expr) for a list of available expressions. |
| delay.duration    | number  | required    |         |            | Duration of the delay. Can be decimal.                                                                                                                      |
| delay.percentage  | integer | optional    |         | [0, 100]   | Percentage of requests to be delayed.                                                                                                                       |
| delay.vars        | array[] | optional    |         |            | Rules which are matched before executing fault injection. See [lua-resty-expr](https://github.com/api7/lua-resty-expr) for a list of available expressions.  |

:::info IMPORTANT

To use the `fault-injection` Plugin one of `abort` or `delay` must be specified.

:::

:::tip

`vars` can have expressions from [lua-resty-expr](https://github.com/api7/lua-resty-expr) and can flexibly implement AND/OR relationship between rules. For example:

```json
[
    [
        [ "arg_name","==","jack" ],
        [ "arg_age","==",18 ]
    ],
    [
        [ "arg_name2","==","allen" ]
    ]
]
```

This means that the relationship between the first two expressions is AND, and the relationship between them and the third expression is OR.

:::

## Enable Plugin

You can enable the `fault-injection` Plugin on a specific Route as shown below:

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
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

Similarly, to enable a `delay` fault:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
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

You can also enable the Plugin with both `abort` and `delay` which can have `vars` for matching:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "plugins": {
        "fault-injection": {
            "abort": {
                "http_status": 403,
                "body": "Fault Injection!\n",
                "vars": [
                    [
                        [ "arg_name","==","jack" ]
                    ]
                ]
            },
            "delay": {
                "duration": 2,
                "vars": [
                    [
                        [ "http_age","==","18" ]
                    ]
                ]
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

## Example usage

Once you have enabled the Plugin as shown above, you can make a request to the configured Route:

```shell
curl http://127.0.0.1:9080/hello -i
```

```
HTTP/1.1 200 OK
Date: Mon, 13 Jan 2020 13:50:04 GMT
Content-Type: text/plain
Transfer-Encoding: chunked
Connection: keep-alive
Server: APISIX web server

Fault Injection!
```

And if we configure the `delay` fault:

```shell
time curl http://127.0.0.1:9080/hello -i
```

```
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

### Fault injection with criteria matching

You can enable the `fault-injection` Plugin with the `vars` attribute to set specific rules:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "plugins": {
        "fault-injection": {
            "abort": {
                    "http_status": 403,
                    "body": "Fault Injection!\n",
                    "vars": [
                        [
                            [ "arg_name","==","jack" ]
                        ]
                    ]
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

Now, we can test the Route. First, we test with a different `name` argument:

```shell
curl "http://127.0.0.1:9080/hello?name=allen" -i
```

You will get the expected response without the fault injected:

```
HTTP/1.1 200 OK
Content-Type: application/octet-stream
Transfer-Encoding: chunked
Connection: keep-alive
Date: Wed, 20 Jan 2021 07:21:57 GMT
Server: APISIX/2.2

hello
```

Now if we set the `name` to match our configuration, the `fault-injection` Plugin is executed:

```shell
curl "http://127.0.0.1:9080/hello?name=jack" -i
```

```
HTTP/1.1 403 Forbidden
Date: Wed, 20 Jan 2021 07:23:37 GMT
Content-Type: text/plain; charset=utf-8
Transfer-Encoding: chunked
Connection: keep-alive
Server: APISIX/2.2

Fault Injection!
```

## Delete Plugin

To remove the `fault-injection` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
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
