---
title: key-auth
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

- [**Name**](#name)
- [**Attributes**](#attributes)
- [**How To Enable**](#how-to-enable)
- [**Test Plugin**](#test-plugin)
- [**Disable Plugin**](#disable-plugin)

## Name

`key-auth` is an authentication plugin, it should work with `consumer` together.

Add Key Authentication (also sometimes referred to as an API key) to a Service or a Route. Consumers then add their key either in a querystring parameter or a header to authenticate their requests.

## Attributes

For consumer side:

| Name | Type   | Requirement | Default | Valid | Description                                                                  |
| ---- | ------ | ----------- | ------- | ----- | ---------------------------------------------------------------------------- |
| key  | string | required    |         |       | different consumer objects should use different values, it should be unique. |

For route side:

| Name | Type   | Requirement | Default | Valid | Description                                                                  |
| ---- | ------ | ----------- | ------- | ----- | ---------------------------------------------------------------------------- |
| header  | string | optional    | apikey        |       | the header we get the key from |

## How To Enable

Two steps are required:

1. creates a consumer object, and set the attributes of plugin `key-auth`.

```shell
curl http://127.0.0.1:9080/apisix/admin/consumers -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "username": "jack",
    "plugins": {
        "key-auth": {
            "key": "auth-one"
        }
    }
}'
```

You can open dashboard with a browser: `http://127.0.0.1:9080/apisix/dashboard/`, to complete the above operation through the web interface, first add a route:
![](../../../assets/images/plugin/key-auth-1.png)

Then add key-auth plugin:
![](../../../assets/images/plugin/key-auth-2.png)

2. creates a route or service object, and enable plugin `key-auth`.

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/index.html",
    "id": 1,
    "plugins": {
        "key-auth": {}
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "39.97.63.215:80": 1
        }
    }
}'
```

If you don't want to fetch key from the default `apikey` header, you can customize the header:

```json
{
    "key-auth": {
        "header": "Authorization"
    }
}
```

## Test Plugin

Here is a correct test example:

```shell
$ curl http://127.0.0.2:9080/index.html -H 'apikey: auth-one' -i
HTTP/1.1 200 OK
...
```

If the request does not set `apikey` correctly, will get a `401` response.

```shell
$ curl http://127.0.0.2:9080/index.html -i
HTTP/1.1 401 Unauthorized
...
{"message":"Missing API key found in request"}

$ curl http://127.0.0.2:9080/index.html -H 'apikey: abcabcabc' -i
HTTP/1.1 401 Unauthorized
...
{"message":"Invalid API key in request"}
```

## Disable Plugin

When you want to disable the `key-auth` plugin, it is very simple,
 you can delete the corresponding json configuration in the plugin configuration,
  no need to restart the service, it will take effect immediately:

```shell
$ curl http://127.0.0.1:2379/v2/keys/apisix/routes/1 -X PUT -d value='
{
    "uri": "/index.html",
    "plugins": {},
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "39.97.63.215:80": 1
        }
    }
}'
```

The `key-auth` plugin has been disabled now. It works for other plugins.
