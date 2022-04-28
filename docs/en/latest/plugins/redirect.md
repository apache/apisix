---
title: redirect
keywords:
  - APISIX
  - Plugin
  - Redirect
description: This document contains information about the Apache APISIX redirect Plugin.
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

The `redirect` Plugin can be used to configure redirects.

## Attributes

| Name          | Type    | Requirement | Default | Valid | Description                                                                                                                                                                                                                                                                                                                                                                                                                        |
| ------------- | ------- | ----------- | ------- | ----- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| http_to_https | boolean | optional    | false   |       | When it is set to `true` and the request is HTTP, will be automatically redirected to HTTPS with 301 response code, and the URI will keep the same as client request.                                                                                                                                                                                                                                                              |
| uri           | string  | optional    |         |       | New URL which can contain Nginx variable, eg: `/test/index.html`, `$uri/index.html`. You can refer to variables in a way similar to `${xxx}` to avoid ambiguity, eg: `${uri}foo/index.html`. If you just need the original `$` character, add `\` in front of it, like this one: `/\$foo/index.html`. If you refer to a variable name that does not exist, this will not produce an error, and it will be used as an empty string. |
| regex_uri | array[string] | optional    |         |                   | Use regular expression to match URL from client, when the match is successful, the URL template will be redirected to. If the match is not successful, the URL from the client will be forwarded to the upstream. Only one of `uri` and `regex_uri` can be exist. For example: [" ^/iresty/(.*)/(.*)/(.*)", "/$1-$2-$3"], the first element represents the matching regular expression and the second element represents the URL template that is redirected to. |
| ret_code      | integer | optional    | 302     |  [200, ...]     | Response code                                                                                                                                                                                                                                                                                                                                                                                                                      |
| ret_port      | integer | optional    | 443     |  [1, 65535]     | Redirect server port, only work when enable `http_to_https`. |
| encode_uri    | boolean | optional    | false   |       | When set to `true` the uri in `Location` header will be encoded  as per [RFC3986](https://datatracker.ietf.org/doc/html/rfc3986) |
| append_query_string    | boolean | optional    | false   |       | When set to `true`, add the query string from the original request to the location header. If the configured `uri` / `regex_uri` already contains a query string, the query string from request will be appended to that after an `&`. Caution: don't use this if you've already handled the query string, e.g. with nginx variable $request_uri, to avoid duplicates. |

:::note

Only one of `http_to_https`, `uri` and `regex_uri` can be configured.

:::

## Enabling the Plugin

The example below shows how you can enable the `redirect` Plugin on a specific Route:

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

You can also use any built-in Nginx variables in the new URI:

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

## Example usage

First, we configure the Plugin as mentioned above. We can then make a request and it will be redirected as shown below:

```shell
curl http://127.0.0.1:9080/test/index.html -i
```

```shell
HTTP/1.1 301 Moved Permanently
Date: Wed, 23 Oct 2019 13:48:23 GMT
Content-Type: text/html
Content-Length: 166
Connection: keep-alive
Location: /test/default.html

...
```

The response shows the response code and the `Location` header implying that the Plugin is in effect.

The example below shows how you can redirect HTTP to HTTPS:

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/hello",
    "plugins": {
        "redirect": {
            "http_to_https": true,
            "ret_port": 9443
        }
    }
}'
```

To test this:

```shell
curl http://127.0.0.1:9080/hello -i
```

```
HTTP/1.1 301 Moved Permanently
...
Location: https://127.0.0.1:9443/hello

...
```

## Disable Plugin

To disable the `redirect` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

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
