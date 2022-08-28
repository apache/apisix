---
title: proxy-rewrite
keywords:
  - APISIX
  - Plugin
  - Proxy Rewrite
  - proxy-rewrite
description: This document contains information about the Apache APISIX proxy-rewrite Plugin.
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

The `proxy-rewrite` Plugin rewrites Upstream proxy information such as `scheme`, `uri` and `host`.

## Attributes

| Name                        | Type          | Required | Default | Valid values                                                                                                                           | Description                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
|-----------------------------|---------------|----------|---------|----------------------------------------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| uri                         | string        | False    |         |                                                                                                                                        | New Upstream forwarding address. Value supports [Nginx variables](https://nginx.org/en/docs/http/ngx_http_core_module.html). For example, `$arg_name`.                                                                                                                                                                                                                                                                                                                       |
| method                      | string        | False    |         | ["GET", "POST", "PUT", "HEAD", "DELETE", "OPTIONS","MKCOL", "COPY", "MOVE", "PROPFIND", "PROPFIND","LOCK", "UNLOCK", "PATCH", "TRACE"] | Rewrites the HTTP method.                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| regex_uri                   | array[string] | False    |         |                                                                                                                                        | New upstream forwarding address. Regular expressions can be used to match the URL from client. If it matches, the URL template is forwarded to the Upstream otherwise, the URL from the client is forwarded. When both `uri` and `regex_uri` are configured, `uri` is used first. For example, `[" ^/iresty/(.*)/(.*)/(.*)", "/$1-$2-$3"]`. Here, the first element is the regular expression to match and the second element is the URL template forwarded to the Upstream. |
| host                        | string        | False    |         |                                                                                                                                        | New Upstream host address.                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| headers                     | object        | False    |         |                                                                                                                                        | New Upstream headers. Headers are overwritten if they are already present otherwise, they are added to the present headers. To remove a header, set the header value to an empty string. The values in the header can contain Nginx variables like `$remote_addr` and `$client_addr`.                                                                                                                                                                                        |
| use_real_request_uri_unsafe | boolean       | False    | false   |                                                                                                                                        | Use real_request_uri (original $request_uri in nginx) to bypass URI normalization. **Enabling this is considered unsafe as it bypasses all URI normalization steps**.                                                                                                                                                                                                                                                                                                     |

## Enabling the Plugin

The example below enables the `proxy-rewrite` Plugin on a specific Route:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/test/index.html",
    "plugins": {
        "proxy-rewrite": {
            "uri": "/test/home.html",
            "host": "iresty.com",
            "headers": {
                "X-Api-Version": "v1",
                "X-Api-Engine": "apisix",
                "X-Api-useless": ""
            }
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

Once you have enabled the Plugin as mentioned below, you can test the Route:

```shell
curl -X GET http://127.0.0.1:9080/test/index.html
```

Once you send the request, you can check the Upstream `access.log` for its output:

```
127.0.0.1 - [26/Sep/2019:10:52:20 +0800] iresty.com GET /test/home.html HTTP/1.1 200 38 - curl/7.29.0 - 0.000 199 107
```

## Disable Plugin

To disable the `proxy-rewrite` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["GET"],
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
