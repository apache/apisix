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

[Chinese](../zh-cn/plugins/consumer-restriction.md)

# Summary
- [**Name**](#name)
- [**Attributes**](#attributes)
- [**How To Enable**](#how-to-enable)
- [**Test Plugin**](#test-plugin)
- [**Disable Plugin**](#disable-plugin)


## Name

The `consumer-restriction` can restrict access to a Service or a Route by either
whitelisting or blacklisting consumers. Support single or multiple consumers.

## Attributes

|Name     |Requirement  |Description|
|---------|--------|-----------|
|whitelist|optional  |List of consumers to whitelist|
|blacklist|optional  |List of consumers to blacklist|

One of `whitelist` or `blacklist` must be specified, and they can not work
together.

## How To Enable

Creates a route or service object, and enable plugin `consumer-restriction`.

```shell
curl http://127.0.0.1:9080/apisix/admin/consumers/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -i -d '
{
    "username": "jack1",
    "plugins": {
        "basic-auth": {
            "username":"jack2019",
            "password": "123456"
        }
    }
}'

curl http://127.0.0.1:9080/apisix/admin/consumers/2 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -i -d '
{
    "username": "jack2",
    "plugins": {
        "basic-auth": {
            "username":"jack2020",
            "password": "123456"
        }
    }
}'

curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/index.html",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    },
    "plugins": {
        "basic-auth": {},
        "consumer-restriction": {
            "whitelist": [
                "jack1"
            ]
        }
    }
}'
```

## Test Plugin

Requests from jack1:

```shell
$ curl -u jack2019:123456 http://127.0.0.1:9080/index.html
HTTP/1.1 200 OK
...
```

Requests from jack2:

```shell
$ curl -u jack2020:123456 http://127.0.0.1:9080/index.html -i
HTTP/1.1 403 Forbidden
...
{"message":"You are not allowed"}
```


## Disable Plugin

When you want to disable the `consumer-restriction` plugin, it is very simple,
you can delete the corresponding json configuration in the plugin configuration,
no need to restart the service, it will take effect immediately:

```shell
$ curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/index.html",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    },
    "plugins": {
        "basic-auth": {}
    }
}'
```

The `consumer-restriction` plugin has been disabled now. It works for other plugins.
