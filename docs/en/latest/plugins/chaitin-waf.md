---
title: chaitin-waf
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - WAF
description: This document contains basic information about the Apache APISIX `chaitin-waf` plugin.
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

After enabling the chaitin-waf plugin, the traffic will be forwarded to the Chaitin WAF service for detection and
prevention of various web application attacks, ensuring the security of the application and user data.

## Response Headers

Depending on the plugin configuration, it is optional to add additional response headers.

The response headers are listed below:

- **X-APISIX-CHAITIN-WAF**: Whether APISIX forwards the request to the WAF server.
    - yes: forwarded
    - no: not forwarded
    - unhealthy: matches the match variables, but no WAF server is available.
    - err: an error occurred during the execution of the plugin. Also includes the **X-APISIX-CHAITIN-WAF-ERROR** header.
    - waf-err: error while interacting with the WAF server. Also includes the **X-APISIX-CHAITIN-WAF-ERROR** header.
    - timeout: request to the WAF server timed out.
- **X-APISIX-CHAITIN-WAF-ERROR**: Debug header. Contains WAF error message.
- **X-APISIX-CHAITIN-WAF-TIME**: The time in milliseconds that APISIX spent interacting with WAF.
- **X-APISIX-CHAITIN-WAF-STATUS**: The status code returned to APISIX by the WAF server.
- **X-APISIX-CHAITIN-WAF-ACTION**: The action returned to APISIX by the WAF server.
    - pass: request valid and passed.
    - reject: request rejected by WAF service.
- **X-APISIX-CHAITIN-WAF-SERVER**: Debug header. Indicates which WAF server was selected.

## Plugin Metadata

| Name                     | Type          | Required | Default value | Description                                                                                                                  |
|--------------------------|---------------|----------|---------------|------------------------------------------------------------------------------------------------------------------------------|
| nodes                    | array(object) | true     |               | A list of addresses for the Chaitin SafeLine WAF service.                                                                    |
| nodes[0].host            | string        | true     |               | The address of Chaitin SafeLine WAF service. Supports IPv4, IPv6, Unix Socket, etc.                                          |
| nodes[0].port            | integer       | false    | 80            | The port of the Chaitin SafeLine WAF service.                                                                                |
| mode                     | string        | false    | block    | The global default mode if a Route doesn't specify its own: `off`, `monitor`, or `block`.     |
| config                   | object        | false    |               | WAF configuration defaults if none are specified on the Route.                                                               |
| config.connect_timeout   | integer       | false    | 1000          | Connect timeout, in milliseconds.                                                                                            |
| config.send_timeout      | integer       | false    | 1000          | Send timeout, in milliseconds.                                                                                               |
| config.read_timeout      | integer       | false    | 1000          | Read timeout, in milliseconds.                                                                                               |
| config.req_body_size     | integer       | false    | 1024          | Request body size, in KB.                                                                                                    |
| config.keepalive_size    | integer       | false    | 256           | Maximum concurrent idle connections to the SafeLine WAF detection service.                                                   |
| config.keepalive_timeout | integer       | false    | 60000         | Idle connection timeout, in milliseconds.                                                                                    |
| config.real_client_ip    | boolean       | false    | true          | Specifies whether to use the `X-Forwarded-For` as the client IP (if present). If `false`, uses the direct client IP from the connection. |

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```bash
curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/chaitin-waf -H "X-API-KEY: $admin_key" -X PUT -d '
{
  "nodes": [
    {
      "host": "unix:/path/to/safeline/resources/detector/snserver.sock",
      "port": 8000
    }
  ],
  "mode": "block",
  "config": {
    "real_client_ip": true
  }
}'

```

## Attributes

| Name                     | Type          | Required | Default value | Description                                                                                                                                                                                                                                                                                                                                               |
|--------------------------|---------------|----------|---------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| mode                     | string        | false    | block         | Determines how the plugin behaves for matched requests. Valid values are `off`, `monitor`, or `block`. When set to `off`, the plugin skips WAF checks. In `monitor` mode, the plugin logs potential blocks without actually blocking the request. In `block` mode, the plugin enforces blocks as determined by the WAF service.                        |
| match                    | array[object] | false    |               | A list of matching rules. The plugin evaluates these rules to decide whether to perform the WAF check on a request. If empty, all requests are processed.                                                                                                                                                                                         |
| match.vars               | array[array]  | false    |               | List of variables used for matching requests. Each rule is specified as `[variable, operator, value]` (for example, `["http_waf", "==", "true"]`). These variables refer to NGINX internal variables. For supported operators, see [lua-resty-expr](https://github.com/api7/lua-resty-expr#operator-list).                                             |
| append_waf_resp_header   | bool          | false    | true          | Determines whether the plugin adds WAF-related response headers (such as `X-APISIX-CHAITIN-WAF`, `X-APISIX-CHAITIN-WAF-ACTION`, etc.) to the response.                                                                                                                                                                                                  |
| append_waf_debug_header  | bool          | false    | false         | Determines whether debugging headers (such as `X-APISIX-CHAITIN-WAF-ERROR` and `X-APISIX-CHAITIN-WAF-SERVER`) are added. Effective only when `append_waf_resp_header` is enabled.                                                                                                                                                                      |
| config                   | object        | false    |               | Provides route-specific configuration for the Chaitin SafeLine WAF service. Settings here override the corresponding metadata defaults when specified.                                                                                                                                                                                                  |
| config.connect_timeout   | integer       | false    | 1000          | The connect timeout for the WAF server, in milliseconds.                                                                                                                                                                                                                                                                                                |
| config.send_timeout      | integer       | false    | 1000          | The send timeout for transmitting data to the WAF server, in milliseconds.                                                                                                                                                                                                                                                                              |
| config.read_timeout      | integer       | false    | 1000          | The read timeout for receiving data from the WAF server, in milliseconds.                                                                                                                                                                                                                                                                               |
| config.req_body_size     | integer       | false    | 1024          | The maximum allowed request body size, in KB.                                                                                                                                                                                                                                                                                                             |
| config.keepalive_size    | integer       | false    | 256           | The maximum number of idle connections to the WAF detection service that can be maintained concurrently.                                                                                                                                                                                                                                                 |
| config.keepalive_timeout | integer       | false    | 60000         | The idle connection timeout for the WAF service, in milliseconds.                                                                                                                                                                                                                                                                                         |
| config.real_client_ip    | boolean       | false    | true          | Specifies whether to determine the client IP from the `X-Forwarded-For` header. If set to `false`, the plugin uses the direct client IP from the connection.                                                                                                                                                                                             |

Below is a sample Route configuration that uses:

- httpbun.org as the upstream backend.
- mode set to monitor, so the plugin only logs potential blocks.
- A matching rule that triggers the plugin when the custom header waf: true is set.
- An override to disable the `real client IP` logic by setting config.real_client_ip to false.

```bash
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
  -H "X-API-KEY: $admin_key" \
  -X PUT -d '
{
   "uri": "/*",
   "plugins": {
       "chaitin-waf": {
           "mode": "monitor",
           "match": [
                {
                    "vars": [
                        ["http_waf", "==", "true"]
                    ]
                }
            ],
           "config": {
               "real_client_ip": false
           },
           "append_waf_resp_header": true,
           "append_waf_debug_header": false
       }
    },
   "upstream": {
       "type": "roundrobin",
       "nodes": {
           "httpbun.org:80": 1
       }
   }
}'
```

## Test Plugin

With the sample configuration described above (including your chosen `mode` and `real_client_ip` settings), the plugin behaves as follows:

- **If the `match` condition is not satisfied** (for example, `waf: true` is missing), the request proceeds normally without contacting the WAF. You can observe:

  ```bash
  curl -H "Host: httpbun.org" http://127.0.0.1:9080/get -i

  HTTP/1.1 200 OK
  Content-Type: application/json
  Content-Length: 408
  Connection: keep-alive
  X-APISIX-CHAITIN-WAF: no
  Date: Wed, 19 Jul 2023 09:30:42 GMT
  X-Powered-By: httpbun/3c0dc05883dd9212ac38b04705037d50b02f2596
  Server: APISIX/3.3.0

  {
    "args": {},
    "headers": {
      "Accept": "*/*",
      "Connection": "close",
      "Host": "httpbun.org",
      "User-Agent": "curl/8.1.2",
      "X-Forwarded-For": "127.0.0.1",
      "X-Forwarded-Host": "httpbun.org",
      "X-Forwarded-Port": "9080",
      "X-Forwarded-Proto": "http",
      "X-Real-Ip": "127.0.0.1"
    },
    "method": "GET",
    "origin": "127.0.0.1, 122.231.76.178",
    "url": "http://httpbun.org/get"
  }
  ```

- **Potential injection requests** (e.g., containing SQL snippets) are forwarded unmodified if they do not meet the plugin’s match rules, and might result in a `404 Not Found` or other response from the upstream:

  ```bash
    curl -H "Host: httpbun.org" http://127.0.0.1:9080/getid=1%20AND%201=1 -i

    HTTP/1.1 404 Not Found
    Content-Type: text/plain; charset=utf-8
    Content-Length: 19
    Connection: keep-alive
    X-APISIX-CHAITIN-WAF: no
    Date: Wed, 19 Jul 2023 09:30:28 GMT
    X-Content-Type-Options: nosniff
    X-Powered-By: httpbun/3c0dc05883dd9212ac38b04705037d50b02f2596
    Server: APISIX/3.3.0

    404 page not found
  ```

- **Matching safe requests** (those that satisfy `match.vars`, such as `-H "waf: true"`) are checked by the WAF. If deemed harmless, you see:

  ```bash
    curl -H "Host: httpbun.org" -H "waf: true" http://127.0.0.1:9080/get -i

    HTTP/1.1 200 OK
    Content-Type: application/json
    Content-Length: 427
    Connection: keep-alive
    X-APISIX-CHAITIN-WAF-TIME: 2
    X-APISIX-CHAITIN-WAF-STATUS: 200
    X-APISIX-CHAITIN-WAF: yes
    X-APISIX-CHAITIN-WAF-ACTION: pass
    Date: Wed, 19 Jul 2023 09:29:58 GMT
    X-Powered-By: httpbun/3c0dc05883dd9212ac38b04705037d50b02f2596
    Server: APISIX/3.3.0

    {
      "args": {},
      "headers": {
        "Accept": "*/*",
        "Connection": "close",
        "Host": "httpbun.org",
        "User-Agent": "curl/8.1.2",
        "Waf": "true",
        "X-Forwarded-For": "127.0.0.1",
        "X-Forwarded-Host": "httpbun.org",
        "X-Forwarded-Port": "9080",
        "X-Forwarded-Proto": "http",
        "X-Real-Ip": "127.0.0.1"
      },
      "method": "GET",
      "origin": "127.0.0.1, 122.231.76.178",
      "url": "http://httpbun.org/get"
    }
  ```

- **Suspicious requests** that meet the plugin’s match rules and are flagged by the WAF are typically rejected with a 403 status, along with headers that include `X-APISIX-CHAITIN-WAF-ACTION: reject`. For example:

  ```bash
    curl -H "Host: httpbun.org" -H "waf: true" http://127.0.0.1:9080/getid=1%20AND%201=1 -i

    HTTP/1.1 403 Forbidden
    Date: Wed, 19 Jul 2023 09:29:06 GMT
    Content-Type: text/plain; charset=utf-8
    Transfer-Encoding: chunked
    Connection: keep-alive
    X-APISIX-CHAITIN-WAF: yes
    X-APISIX-CHAITIN-WAF-TIME: 2
    X-APISIX-CHAITIN-WAF-ACTION: reject
    X-APISIX-CHAITIN-WAF-STATUS: 403
    Server: APISIX/3.3.0
    Set-Cookie: sl-session=UdywdGL+uGS7q8xMfnJlbQ==; Domain=; Path=/; Max-Age=86400

    {"code": 403, "success":false, "message": "blocked by Chaitin SafeLine Web Application Firewall", "event_id": "51a268653f2c4189bfa3ec66afbcb26d"}
  ```

## Delete Plugin

To remove the `chaitin-waf` plugin, you can delete the corresponding JSON configuration from the Plugin configuration.
APISIX will automatically reload and you do not have to restart for this to take effect:

```bash
$ curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
{
   "uri": "/*",
   "upstream": {
       "type": "roundrobin",
       "nodes": {
           "httpbun.org:80": 1
       }
   }
}'
```
