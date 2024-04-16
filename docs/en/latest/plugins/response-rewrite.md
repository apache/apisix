---
title: response-rewrite
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - Response Rewrite
  - response-rewrite
description: This document contains information about the Apache APISIX response-rewrite Plugin.
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

The `response-rewrite` Plugin rewrites the content returned by the [Upstream](../terminology/upstream.md) and APISIX.

This Plugin can be useful in these scenarios:

- To set `Access-Control-Allow-*` field for supporting [CORS](https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS).
- To set custom `status_code` and `Location` fields in the header to redirect.

:::tip

You can also use the [redirect](./redirect.md) Plugin to setup redirects.

:::

## Attributes

| Name            | Type    | Required | Default | Valid values                                                                                                  | Description                                                                                                                                                                                                                                                                         |
|-----------------|---------|----------|---------|---------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| status_code     | integer | False    |         | [200, 598]                                                                                                    | New HTTP status code in the response. If unset, falls back to the original status code.                                                                                                                                                                                             |
| body            | string  | False    |         |                                                                                                               | New body of the response. The content-length would also be reset.                                                                                                                                                                                                                   |
| body_base64     | boolean | False    | false   |                                                                                                               | When set, the body passed in `body` will be decoded before writing to the client which is used in some image and Protobuffer scenarios. Note that this field only allows decoding the body passed in plugin configuration and does not decode upstream response.                                                                                                                                                                                                       |
| headers         | object  | False    |         |                                                                                                               |                                                                                                                                                                                                                                                                                     |
| headers.add     | array   | False    |         |                                                                                                               | Append the new headers to the response. The format is `["name: value", ...]`. The values in the header can contain Nginx variables like `$remote_addr` and `$balancer_ip`.                                                                                                          |
| headers.set     | object  | False    |         |                                                                                                               | Rewriting the headers. The format is `{"name": "value", ...}`. The values in the header can contain Nginx variables like `$remote_addr` and `$balancer_ip`. |
| headers.remove  | array   | False    |         |                                                                                                               | Remove the headers. The format is `["name", ...]`.                                                                                                                                                                                                                                  |
| vars            | array[] | False    |         | See [lua-resty-expr](https://github.com/api7/lua-resty-expr#operator-list) for a list of available operators. | Nginx variable expressions to conditionally execute the rewrite. The Plugin will be executed unconditionally if this value is empty.                                                                                                                                                |
| filters         | array[] | False    |         |                                                                                                               | List of filters that modify the response body by replacing one specified string with another.                                                                                                                                                                                       |
| filters.regex   | string  | True     |         |                                                                                                               | Regex pattern to match on the response body.                                                                                                                                                                                                                                        |
| filters.scope   | string  | False    | "once"  | "once","global"                                                                                               | Range to substitute. `once` substitutes the first match of `filters.regex` and `global` does global substitution.                                                                                                                                                                   |
| filters.replace | string  | True     |         |                                                                                                               | Content to substitute with.                                                                                                                                                                                                                                                         |
| filters.options | string  | False    | "jo"    |                                                                                                               | Regex options. See [ngx.re.match](https://github.com/openresty/lua-nginx-module#ngxrematch).                                                                                                                                                                                        |

:::note

Only one of `body` or `filters` can be configured.

:::

## Enable Plugin

The example below enables the `response-rewrite` Plugin on a specific Route:

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/test/index.html",
    "plugins": {
        "response-rewrite": {
            "body": "{\"code\":\"ok\",\"message\":\"new json body\"}",
            "headers": {
                "set": {
                    "X-Server-id": 3,
                    "X-Server-status": "on",
                    "X-Server-balancer-addr": "$balancer_ip:$balancer_port"
                }
            },
            "vars":[
                [ "status","==",200 ]
            ]
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

Here, `vars` is configured to run the Plugin only on responses with a 200 status code.

Besides `set` operation, you can also `add` or `remove` response header like:

```json
"headers": {
    "add": [
        "X-Server-balancer-addr: $balancer_ip:$balancer_port"
    ],
    "remove": [
        "X-TO-BE-REMOVED"
    ]
}
```

The execution order among those operations are ["add", "set", "remove"].

If you are using the deprecated `headers` configuration which puts the headers directly under `headers`,
you need to move them to `headers.set`.

## Example usage

Once you have enabled the Plugin as shown above, you can make a request:

```shell
curl -X GET -i  http://127.0.0.1:9080/test/index.html
```

The response will be as shown below no matter what the response is from the Upstream:

```
HTTP/1.1 200 OK
Date: Sat, 16 Nov 2019 09:15:12 GMT
Transfer-Encoding: chunked
Connection: keep-alive
X-Server-id: 3
X-Server-status: on
X-Server-balancer-addr: 127.0.0.1:80

{"code":"ok","message":"new json body"}
```

:::info IMPORTANT

[ngx.exit](https://openresty-reference.readthedocs.io/en/latest/Lua_Nginx_API/#ngxexit) will interrupt the execution of a request and returns its status code to Nginx.

However, if `ngx.exit` is executed during an access phase, it will only interrupt the request processing phase and the response phase will still continue to run.

So, if you have configured the `response-rewrite` Plugin, it do a force overwrite of the response.

| Phase         | rewrite  | access   | header_filter | body_filter |
|---------------|----------|----------|---------------|-------------|
| rewrite       | ngx.exit | √        | √             | √           |
| access        | ×        | ngx.exit | √             | √           |
| header_filter | √        | √        | ngx.exit      | √           |
| body_filter   | √        | √        | ×             | ngx.exit    |

:::

The example below shows how you can replace a key in the response body. Here, the key X-Amzn-Trace-Id is replaced with X-Amzn-Trace-Id-Replace by configuring the filters attribute using regex:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
{
  "plugins":{
    "response-rewrite":{
      "headers":{
        "set": {
            "X-Server-id":3,
            "X-Server-status":"on",
            "X-Server-balancer-addr":"$balancer_ip:$balancer_port"
        }
      },
      "filters":[
        {
          "regex":"X-Amzn-Trace-Id",
          "scope":"global",
          "replace":"X-Amzn-Trace-Id-Replace"
        }
      ],
      "vars":[
        [
          "status",
          "==",
          200
        ]
      ]
    }
  },
  "upstream":{
    "type":"roundrobin",
    "scheme":"https",
    "nodes":{
      "httpbin.org:443":1
    }
  },
  "uri":"/*"
}'
```

```shell
curl -X GET -i  http://127.0.0.1:9080/get
```

```shell
HTTP/1.1 200 OK
Transfer-Encoding: chunked
X-Server-status: on
X-Server-balancer-addr: 34.206.80.189:443
X-Server-id: 3

{
  "args": {},
  "headers": {
    "Accept": "*/*",
    "Host": "127.0.0.1",
    "User-Agent": "curl/7.29.0",
    "X-Amzn-Trace-Id-Replace": "Root=1-629e0b89-1e274fdd7c23ca6e64145aa2",
    "X-Forwarded-Host": "127.0.0.1"
  },
  "origin": "127.0.0.1, 117.136.46.203",
  "url": "https://127.0.0.1/get"
}

```

## Delete Plugin

To remove the `response-rewrite` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/test/index.html",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:80": 1
        }
    }
}'
```
