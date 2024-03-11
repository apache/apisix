---
title: proxy-rewrite
keywords:
  - Apache APISIX
  - API Gateway
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
| regex_uri                   | array[string] | False    |         |                                                                                                                                        | Regular expressions can be used to match the URL from client. If it matches, the URL template is forwarded to the upstream. Otherwise, the URL from the client is forwarded. When both `uri` and `regex_uri` are configured, `uri` has a higher priority. Multiple regular expressions are currently supported for pattern matching, and the plugin will try to match them one by one until they succeed or all fail. For example: `["^/iresty/(. *)/(. *)/(. *)", "/$1-$2-$3", ^/theothers/(. *)/(. *)", "/theothers/$1-$2"]`, the element with the odd index represents the uri regular expression that matches the request from the client, and the element with the even index represents the `uri` template that is forwarded upstream upon a successful match. Please note that the length of this value must be an **even number**. |
| host                        | string        | False    |         |                                                                                                                                        | New Upstream host address.                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| headers                     | object        | False    |         |                                                                                                                                   |                   |
| headers.add     | object   | false     |        |                 | Append the new headers. The format is `{"name": "value",...}`. The values in the header can contain Nginx variables like `$remote_addr` and `$balancer_ip`. It also supports referencing the match result of `regex_uri` as a variable like `$1-$2-$3`.                                                                                              |
| headers.set     | object  | false     |        |                 | Overwrite the headers. If the header does not exist, it will be added. The format is  `{"name": "value", ...}`. The values in the header can contain Nginx variables like `$remote_addr` and `$balancer_ip`. It also supports referencing the match result of `regex_uri` as a variable like `$1-$2-$3`. Note that if you would like to set the `Host` header, use the `host` attribute instead.                                                                                       |
| headers.remove  | array   | false     |        |                 | Remove the headers. The format is `["name", ...]`.
| use_real_request_uri_unsafe | boolean       | False    | false   |                                                                                                                                        | Use real_request_uri (original $request_uri in nginx) to bypass URI normalization. **Enabling this is considered unsafe as it bypasses all URI normalization steps**.                                                                                                                                                                                                                                                                                                     |

## Header Priority

Header configurations are executed according to the following priorities:

`add` > `remove` > `set`

## Enable Plugin

The example below enables the `proxy-rewrite` Plugin on a specific Route:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "id": "proxy-rewrite-route",
    "methods": ["GET"],
    "uri": "/headers",
    "plugins": {
      "proxy-rewrite": {
        "host": "myapisix.demo"
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
curl "http://127.0.0.1:9080/headers"
```

You should see a response similar to the following:

```
{
  "headers": {
    "Accept": "*/*",
    "Host": "myapisix.demo",
    "User-Agent": "curl/8.2.1",
    "X-Amzn-Trace-Id": "Root=1-64fef198-29da0970383150175bd2d76d",
    "X-Forwarded-Host": "127.0.0.1"
  }
}
```

## Delete Plugin

To remove the `proxy-rewrite` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "id": "proxy-rewrite-route",
    "methods": ["GET"],
    "uri": "/headers",
    "plugins": {},
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "127.0.0.1:80": 1
      }
    }
  }'
```
