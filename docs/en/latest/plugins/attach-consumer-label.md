---
title: attach-consumer-label
keywords:
  - Apache APISIX
  - API Gateway
  - API Consumer
description: This article describes the Apache APISIX attach-consumer-label plugin, which you can use to pass custom consumer labels to upstream services.
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

The `attach-consumer-label` plugin attaches custom consumer-related labels, in addition to `X-Consumer-Username` and `X-Credential-Indentifier`, to authenticated requests, for upstream services to differentiate between consumers and implement additional logics.

## Attributes

| Name     | Type   | Required | Default | Valid values | Description                                                                                                                                                                                                                                                                                                                                                                                                     |
|----------|--------|----------|---------|--------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| headers  | object | True     |         |              | Key-value pairs of consumer labels to be attached to request headers, where key is the request header name, such as `X-Consumer-Role`, and the value is a reference to the custom label key, such as `$role`. Note that the value should always start with a dollar sign (`$`). If a referenced consumer value is not configured on the consumer, the corresponding header will not be attached to the request. |

## Enable Plugin

The following example demonstrates how you can attach custom labels to request headers before authenticated requests are forwarded to upstream services. If the request is rejected, you should not see any consumer labels attached to request headers. If a certain label value is not configured on the consumer but referenced in the `attach-consumer-label` plugin, the corresponding header will also not be attached.

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

Create a consumer `john` with custom labels:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "username": "john",
    "labels": {
      "department": "devops",
      "company": "api7"
    }
  }'
```

Configure the `key-auth` credential for the consumer `john`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/john/credentials" -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "id": "cred-john-key-auth",
    "plugins": {
      "key-auth": {
        "key": "john-key"
      }
    }
  }'
```

Create a route enabling the `key-auth` and `attach-consumer-label` plugins:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "id": "attach-consumer-label-route",
    "uri": "/get",
    "plugins": {
      "key-auth": {},
      "attach-consumer-label": {
        "headers": {
          "X-Consumer-Department": "$department",
          "X-Consumer-Company": "$company",
          "X-Consumer-Role": "$role"
        }
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```

:::tip

The consumer label references must be prefixed by a dollar sign (`$`).

:::

To verify, send a request to the route with the valid credential:

```shell
curl -i "http://127.0.0.1:9080/get" -H 'apikey: john-key'
```

You should see an `HTTP/1.1 200 OK` response similar to the following:

```json
{
  "args": {},
  "headers": {
    "Accept": "*/*",
    "Apikey": "john-key",
    "Host": "127.0.0.1",
    "X-Consumer-Username": "john",
    "X-Credential-Indentifier": "cred-john-key-auth",
    "X-Consumer-Company": "api7",
    "X-Consumer-Department": "devops",
    "User-Agent": "curl/8.6.0",
    "X-Amzn-Trace-Id": "Root=1-66e5107c-5bb3e24f2de5baf733aec1cc",
    "X-Forwarded-Host": "127.0.0.1"
  },
  "origin": "192.168.65.1, 205.198.122.37",
  "url": "http://127.0.0.1/get"
}
```

## Delete plugin

To remove the Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/attach-consumer-label-route" -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "uri": "/get",
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```
