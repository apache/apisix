---
title: attach-consumer-label
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - attach-consumer-label
  - Consumer
description: The attach-consumer-label Plugin attaches custom Consumer labels to authenticated requests, for Upstream services to implement additional business logic.
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

 <head>
   <link rel="canonical" href="https://docs.api7.ai/hub/attach-consumer-label" />
 </head>

## Description

The `attach-consumer-label` Plugin attaches custom consumer-related labels, in addition to `X-Consumer-Username` and `X-Credential-Identifier`, to authenticated requests, for Upstream services to differentiate between consumers and implement additional logic.

## Attributes

| Name     | Type   | Required | Default | Valid values | Description                                                                                                                                                                                                                                                                                                                                                                                                     |
|----------|--------|----------|---------|--------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| headers  | object | True     |         |              | Key-value pairs of Consumer labels to be attached to request headers, where key is the request header name, such as `X-Consumer-Role`, and the value is a reference to the custom label key, such as `$role`. Note that the value should always start with a dollar sign (`$`). If a referenced Consumer label value is not configured on the Consumer, the corresponding header will not be attached to the request. |

## Examples

The following example demonstrates how you can attach custom labels to request headers before authenticated requests are forwarded to Upstream services. If the request is rejected, you should not see any Consumer labels attached to request headers. If a certain label value is not configured on the Consumer but referenced in the `attach-consumer-label` Plugin, the corresponding header will also not be attached.

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Attach Consumer Labels

Create a Consumer `john` with custom labels:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "john",
    "labels": {
      "department": "devops",
      "company": "api7"
    }
  }'
```

Configure the `key-auth` Credential for the Consumer `john`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/john/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-john-key-auth",
    "plugins": {
      "key-auth": {
        "key": "john-key"
      }
    }
  }'
```

Create a Route enabling the `key-auth` and `attach-consumer-label` Plugins:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
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

- `X-Consumer-Department`: attaches the `department` Consumer label value.
- `X-Consumer-Company`: attaches the `company` Consumer label value.
- `X-Consumer-Role`: attaches the `role` Consumer label value. As the `role` label is not configured on the Consumer, it is expected that the header will not appear in the request forwarded to the Upstream service.

:::tip

Consumer label references must be prefixed by a dollar sign (`$`).

:::

To verify, send a request to the Route with the valid Credential:

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
    "X-Credential-Identifier": "cred-john-key-auth",
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

Note that `X-Consumer-Role` is not present in the response because the `role` label was not configured on the Consumer.
