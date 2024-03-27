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

After enabling the chaitin-waf plugin, the traffic will be forwarded to the Chaitin WAF service for the detection and
prevention of various web application attacks, ensuring the security of the application and user data.

## Response Headers

Depending on the plugin configuration, it is optional to add additional response headers.

The response headers are listed below:

- **X-APISIX-CHAITIN-WAF**: Whether APISIX forwards the request to the WAF server.
    - yes: forwarded
    - no: no forwarded
    - unhealthy: matches the match variables, but no WAF server is available.
    - err: an error occurred during the execution of the plugin. Also with **X-APISIX-CHAITIN-WAF-ERROR** request header
    - waf-err: Error while interacting with the WAF server. Also with **X-APISIX-CHAITIN-WAF-ERROR** request header
    - timeout: Timeout for request to the WAF server
- **X-APISIX-CHAITIN-WAF-ERROR**: Debug header. WAF error message
- **X-APISIX-CHAITIN-WAF-TIME**: The time in milliseconds that APISIX spent interacting with WAF.
- **X-APISIX-CHAITIN-WAF-STATUS**: The status code returned to APISIX by the WAF server.
- **X-APISIX-CHAITIN-WAF-ACTION**: Processing result returned to APISIX by the WAF server.
    - pass: request valid and passed
    - reject: request rejected by WAF service
- **X-APISIX-CHAITIN-WAF-SERVER**: Debug header. Picked WAF server.

## Plugin Metadata

| Name                     | Type          | Required | Default value | Description                                                                                                                  |
|--------------------------|---------------|----------|---------------|------------------------------------------------------------------------------------------------------------------------------|
| nodes                    | array(object) | true     |               | A list of addresses for the Chaitin SafeLine WAF service.                                                                    |
| nodes[0].host            | string        | true     |               | The address of Chaitin SafeLine WAF service. Supports IPV4, IPV6, Unix Socket, etc.                                          |
| nodes[0].port            | string        | false    | 80            | The port of Chaitin SafeLine WAF service.                                                                                    |
| config                   | object        | false    |               | Configuration of the Chaitin SafeLine WAF service. The parameters configured here will be used when route is not configured. |
| config.connect_timeout   | integer       | false    | 1000          | connect timeout, in milliseconds                                                                                             |
| config.send_timeout      | integer       | false    | 1000          | send timeout, in milliseconds                                                                                                |
| config.read_timeout      | integer       | false    | 1000          | read timeout, in milliseconds                                                                                                |
| config.req_body_size     | integer       | false    | 1024          | request body size, in KB                                                                                                     |
| config.keepalive_size    | integer       | false    | 256           | maximum concurrent idle connections to the SafeLine WAF detection service                                                    |
| config.keepalive_timeout | integer       | false    | 60000         | idle connection timeout, in milliseconds                                                                                     |

An example configuration is as follows.

```bash
curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/chaitin-waf -H "X-API-KEY: $admin_key" -X PUT -d '
{
  "nodes":[
     {
       "host": "unix:/path/to/safeline/resources/detector/snserver.sock",
       "port": 8000
     }
  ]
}'
```

## Attributes

| Name                     | Type          | Required | Default value | Description                                                                                                                                                                                                                                                                                                                                               |
|--------------------------|---------------|----------|---------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| match                    | array[object] | false    |               | The list of matching rules, default is empty                                                                                                                                                                                                                                                                                                              |
| match.vars               | array[array]  | false    |               | List of variables to match for filtering requests for conditional traffic split. It is in the format `{variable operator value}`. For example, `{"arg_name", "==", "json"}`. The variables here are consistent with NGINX internal variables. For details on supported operators, [lua-resty-expr](https://github.com/api7/lua-resty-expr#operator-list). |
| append_waf_resp_header   | bool          | false    | true          | Whether to add response headers                                                                                                                                                                                                                                                                                                                           |
| append_waf_debug_header  | bool          | false    | false         | Whether or not to add debugging headers, effective when `add_header` is `true`.                                                                                                                                                                                                                                                                           |
| config                   | object        | false    |               | Configuration of the Chaitin SafeLine WAF service. When the route is not configured, the parameters configured in the metadata are used.                                                                                                                                                                                                                  |
| config.connect_timeout   | integer       | false    |               | connect timeout, in milliseconds                                                                                                                                                                                                                                                                                                                          |
| config.send_timeout      | integer       | false    |               | send timeout, in milliseconds                                                                                                                                                                                                                                                                                                                             |
| config.read_timeout      | integer       | false    |               | read timeout, in milliseconds                                                                                                                                                                                                                                                                                                                             |
| config.req_body_size     | integer       | false    |               | request body size, in KB                                                                                                                                                                                                                                                                                                                                  |
| config.keepalive_size    | integer       | false    |               | maximum concurrent idle connections to the SafeLine WAF detection service                                                                                                                                                                                                                                                                                 |
| config.keepalive_timeout | integer       | false    |               | idle connection timeout, in milliseconds                                                                                                                                                                                                                                                                                                                  |

A sample configuration is shown below, using `httpbun.org` as the example backend, which can be replaced as needed:

```bash
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
{
   "uri": "/*",
   "plugins": {
       "chaitin-waf": {
           "match": [
                {
                    "vars": [
                        ["http_waf","==","true"]
                    ]
                }
            ]
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

Test the above example configuration.

If the match condition is not met, the request can be reached normally:

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

Potential injection requests are also forwarded as is and encounter a 404 error:

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

Normal requests are still reachable when the match condition is met:

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

Potential attack requests will be intercepted and returned a 403 error:

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
