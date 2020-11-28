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

- [中文](../zh-cn/plugins/redirect.md)

# Summary
- [**Name**](#name)
- [**Attributes**](#attributes)
- [**How To Enable**](#how-to-enable)
- [**Test Plugin**](#test-plugin)
- [**Disable Plugin**](#disable-plugin)

## Name

URI redirect.

## Attributes

| Name          | Type    | Requirement | Default | Valid | Description                                                                                                                                                                                                                                                                                                                                                                                                                        |
| ------------- | ------- | ----------- | ------- | ----- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| http_to_https | boolean | optional    | false   |       | When it is set to `true` and the request is HTTP, will be automatically redirected to HTTPS with 301 response code, and the URI will keep the same as client request.                                                                                                                                                                                                                                                              |
| uri           | string  | optional    |         |       | New URL which can contain Nginx variable, eg: `/test/index.html`, `$uri/index.html`. You can refer to variables in a way similar to `${xxx}` to avoid ambiguity, eg: `${uri}foo/index.html`. If you just need the original `$` character, add `\` in front of it, like this one: `/\$foo/index.html`. If you refer to a variable name that does not exist, this will not produce an error, and it will be used as an empty string. |
| ret_code      | string  | optional    | 302     |  [200, ...]     | Response code                                                                                                                                                                                                                                                                                                                                                                                                                      |

One of `http_to_https` and `uri` need to be specified.

## How To Enable

Here's a mini example, enable the `redirect` plugin on the specified route:

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/test/index.html",
    "plugins": {
        "redirect": {
            "uri": "/test/default.html",
            "ret_code": 301
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:80": 1
        }
    }
}'
```

And we can use any Nginx built-in variable in the new URI.

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/test",
    "plugins": {
        "redirect": {
            "uri": "$uri/index.html",
            "ret_code": 301
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:80": 1
        }
    }
}'
```

## Test Plugin

Testing based on the above examples :

```shell
$ curl http://127.0.0.1:9080/test/index.html -i
HTTP/1.1 301 Moved Permanently
Date: Wed, 23 Oct 2019 13:48:23 GMT
Content-Type: text/html
Content-Length: 166
Connection: keep-alive
Location: /test/default.html

...
```

We can check the response code and the response header `Location`.

It shows that the `redirect` plugin is in effect.

 Here is an example of redirect HTTP to HTTPS:
```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/hello",
    "plugins": {
        "redirect": {
            "http_to_https": true
        }
    }
}'
```

## Disable Plugin

When you want to disable the `redirect` plugin, it is very simple,
 you can delete the corresponding json configuration in the plugin configuration,
  no need to restart the service, it will take effect immediately :

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/test/index.html",
    "plugins": {},
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:80": 1
        }
    }
}'
```

The `redirect` plugin has been disabled now. It works for other plugins.
