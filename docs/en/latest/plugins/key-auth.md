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

## Description

We could use the `key-auth` plugin to protect `Routes` and `Services`.

**NOTE**: We need to bind this plugin with `Consumer` first, then bind it with `Route` or `Service`.

## Parameters

### Bind plugin with Consumer

| Name | Type   | Required | Default | Description                                                                                       |
| ---- | ------ | -------- | ------- | ------------------------------------------------------------------------------------------------- |
| key  | String | Yes      |         | Consumers will use this key to access the resource for authentication, this key should be unique. |

### Bind plugin with Route/Service

| Name   | Type   | Required | Default | Description                                                          |
| ------ | ------ | -------- | ------- | -------------------------------------------------------------------- |
| header | String | False    | apikey  | The plugin will get API Key from target header, default to `apikey`. |

## How to enable

Firstly, please create a `Consumer` and bind this plugin, we will use `auth-key` as key's value: 

```bash
$ curl -X PUT http://127.0.0.1:9080/apisix/admin/consumers -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" -d '
{
  "username": "jack",
  "plugins": {
    "key-auth": {
      "key": "auth-key"
    }
  }
}
'
```

Secondly, please create a `Route` and bind this plugin, no configuration needed:

```bash
$ curl -X PUT http://127.0.0.1:9080/apisix/admin/routes/1 -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" -d '
{
  "methods": ["GET"],
  "uri": "/get",
  "plugins": {
    "key-auth": {}
  },
  "upstream": {
    "type": "roundrobin",
    "nodes": {
      "httpbin.org:80": 1
    }
  }
}
'
```

Let's have a test:

```bash
# Scenario 1: Access the route without key

## Request
$ curl -i -X GET http://127.0.0.1:9080/get

## Response
HTTP/1.1 401 Unauthorized
Date: Wed, 28 Apr 2021 09:02:40 GMT
Content-Type: text/plain; charset=utf-8
Transfer-Encoding: chunked
Connection: keep-alive
Server: APISIX/2.5

{"message":"Missing API key found in request"}

# Scenario 2: Access the route with wrong key

## Request
$ curl -i -X GET http://127.0.0.1:9080/get -H "apikey: wrong-key"

## Response
HTTP/1.1 401 Unauthorized
Date: Wed, 28 Apr 2021 09:03:40 GMT
Content-Type: text/plain; charset=utf-8
Transfer-Encoding: chunked
Connection: keep-alive
Server: APISIX/2.5

{"message":"Invalid API key in request"}

# Scenario 3: Access the route with correct key (in the HTTP Header)

## Request
$ curl -i -X GET http://127.0.0.1:9080/get -H "apikey: auth-key"

## Response
HTTP/1.1 200 OK
Content-Type: application/json
Content-Length: 325
Connection: keep-alive
Date: Wed, 28 Apr 2021 09:03:53 GMT
Access-Control-Allow-Origin: *
Access-Control-Allow-Credentials: true
Server: APISIX/2.5

{
  "args": {},
  "headers": {
    "Accept": "*/*",
    "Apikey": "auth-key",
    "Host": "127.0.0.1",
    "User-Agent": "curl/7.29.0",
    "X-Amzn-Trace-Id": "Root=1-608924f9-4a20a14821ce0ae97337e9f8",
    "X-Forwarded-Host": "127.0.0.1"
  },
  "origin": "127.0.0.1, 8.210.41.192",
  "url": "http://127.0.0.1/get"
}
```

## How to disable

Just updated the Route configuration without that plugin:

```bash
$ curl -X PUT http://127.0.0.1:9080/apisix/admin/routes/1 -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" -d '
{
  "methods": ["GET"],
  "uri": "/get",
  "plugins": {},
  "upstream": {
    "type": "roundrobin",
    "nodes": {
      "httpbin.org:80": 1
    }
  }
}
'
```
