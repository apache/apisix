---
title: redirect
keywords:
  - Apache APISIX
  - API Gateway
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

| Name                | Type          | Required | Default | Valid values | Description                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
|---------------------|---------------|----------|---------|--------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| http_to_https       | boolean       | False    | false   |              | When set to `true` and the request is HTTP, it will be redirected to HTTPS with the same URI with a 301 status code.  Note the querystring from the raw URI will also be contained in the Location header.                                                                                                                                                                                                                                                          |
| uri                 | string        | False    |         |              | URI to redirect to. Can contain Nginx variables. For example, `/test/index.html`, `$uri/index.html`, `${uri}/index.html`, `https://example.com/foo/bar`. If you refer to a variable name that doesn't exist, instead of throwing an error, it will treat it as an empty variable.                                                                                                                                                                                   |
| regex_uri           | array[string] | False    |         |              | Match the URL from client with a regular expression and redirect. If it doesn't match, the request will be forwarded to the Upstream. Only either of `uri` or `regex_uri` can be used at a time. For example, [" ^/iresty/(.*)/(.*)/(.*)", "/$1-$2-$3"], where the first element is the regular expression to match and the second element is the URI to redirect to. APISIX only support one `regex_uri` currently, so the length of the `regex_uri` array is `2`. |
| ret_code            | integer       | False    | 302     | [200, ...]   | HTTP response code.                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| encode_uri          | boolean       | False    | false   |              | When set to `true` the URI in the `Location` header will be encoded as per [RFC3986](https://datatracker.ietf.org/doc/html/rfc3986).                                                                                                                                                                                                                                                                                                                                |
| append_query_string | boolean       | False    | false   |              | When set to `true`, adds the query string from the original request to the `Location` header. If the configured `uri` or `regex_uri` already contains a query string, the query string from the request will be appended to it with an `&`. Do not use this if you have already handled the query string (for example, with an Nginx variable `$request_uri`) to avoid duplicates.                                                                                  |

:::note

* Only one of `http_to_https`, `uri` and `regex_uri` can be configured.
* Only one of `http_to_https` and `append_query_string` can be configured.
* When enabling `http_to_https`, the ports in the redirect URL will pick a value in the following order (in descending order of priority)
  * Read `plugin_attr.redirect.https_port` from the configuration file (`conf/config.yaml`).
  * If `apisix.ssl` is enabled, read `apisix.ssl.listen` and select a port randomly from it.
  * Use 443 as the default https port.

:::

## Enable Plugin

The example below shows how you can enable the `redirect` Plugin on a specific Route:

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  -H "X-API-KEY: $admin_key" -X PUT -d '
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
curl http://127.0.0.1:9180/apisix/admin/routes/1  -H "X-API-KEY: $admin_key" -X PUT -d '
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
curl http://127.0.0.1:9180/apisix/admin/routes/1  -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/hello",
    "plugins": {
        "redirect": {
            "http_to_https": true
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

## Delete Plugin

To remove the `redirect` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  -H "X-API-KEY: $admin_key" -X PUT -d '
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
