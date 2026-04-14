---
title: workflow
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - workflow
  - traffic control
description: The workflow Plugin supports the conditional execution of user-defined actions to client traffic based a given set of rules. This provides a granular approach to implement complex traffic management.
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
  <link rel="canonical" href="https://docs.api7.ai/hub/workflow" />
</head>

## Description

The `workflow` Plugin supports the conditional execution of user-defined actions to client traffic based a given set of rules, defined using [lua-resty-expr](https://github.com/api7/lua-resty-expr#operator-list). This provides a granular approach to traffic management.

## Attributes

| Name                         | Type          | Required | Default | Valid values | Description                                                  |
| ---------------------------- | ------------- | -------- | ------- | ------------ | ------------------------------------------------------------ |
| rules                   | array[object]  | True     |         |              |  An array of one or more pairs of matching conditions and actions to be executed. |
| rules.case                   | array[array]  | False     |         |              | An array of one or more matching conditions in the form of [lua-resty-expr](https://github.com/api7/lua-resty-expr#operator-list). For example, `{"arg_name", "==", "json"}`.  |
| rules.actions                | array[object] | True     |         |              | An array of actions to be executed when a condition is successfully matched. Currently, the array only supports one action, and it should be either `return`, or `limit-count` or `limit-conn`. When the action is configured to be `return`, you can configure an HTTP status code to return to the client when the condition is matched. When the action is configured to be `limit-count`, you can configure all options of the [`limit-count`](./limit-count.md) plugin, except for `group`. When the action is configured to be `limit-conn`, you can configure all options of the [`limit-conn`](./limit-conn.md) plugin. |

## Examples

The examples below demonstrates how you can use the `workflow` Plugin for different scenarios.

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Return Response HTTP Status Code Conditionally

The following example demonstrates a simple rule with one matching condition and one associated action to return HTTP status code conditionally.

Create a Route with the `workflow` Plugin to return HTTP status code 403 when the request's URI path is `/anything/rejected`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "workflow-route",
    "uri": "/anything/*",
    "plugins": {
      "workflow":{
        "rules":[
          {
            "case":[
              ["uri", "==", "/anything/rejected"]
            ],
            "actions":[
              [
                "return",
                {"code": 403}
              ]
            ]
          }
        ]
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org": 1
      }
    }
  }'
```

Send a request that matches none of the rules:

```shell
curl -i "http://127.0.0.1:9080/anything/anything"
```

You should receive an `HTTP/1.1 200 OK` response.

Send a request that matches the configured rule:

```shell
curl -i "http://127.0.0.1:9080/anything/rejected"
```

You should receive an `HTTP/1.1 403 Forbidden` response of following:

```text
{"error_msg":"rejected by workflow"}
```

### Apply Rate Limiting Conditionally by URI and Query Parameter

The following example demonstrates a rule with two matching conditions and one associated action to rate limit requests conditionally.

Create a Route with the `workflow` Plugin to apply rate limiting when the URI path is `/anything/rate-limit` and the query parameter `env` value is `v1`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "workflow-route",
    "uri": "/anything/*",
    "plugins":{
      "workflow":{
        "rules":[
          {
            "case":[
              ["uri", "==", "/anything/rate-limit"],
              ["arg_env", "==", "v1"]
            ],
            "actions":[
              [
                "limit-count",
                {
                  "count":1,
                  "time_window":60,
                  "rejected_code":429
                }
              ]
            ]
          }
        ]
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org": 1
      }
    }
  }'
```

Generate two consecutive requests that matches the second rule:

```shell
curl -i "http://127.0.0.1:9080/anything/rate-limit?env=v1"
```

You should receive an `HTTP/1.1 200 OK` response and an `HTTP 429 Too Many Requests` response.

Generate requests that do not match the condition:

```shell
curl -i "http://127.0.0.1:9080/anything/anything?env=v1"
```

You should receive `HTTP/1.1 200 OK` responses for all requests, as they are not rate limited.

### Apply Rate Limiting Conditionally by Consumers

The following example demonstrates how to configure the Plugin to perform rate limiting based on the following specifications:

* Consumer `john` should have a quota of 5 requests within a 30-second window
* Consumer `jane` should have a quota of 3 requests within a 30-second window
* All other consumers should have a quota of 2 requests within a 30-second window

While this example will be using [`key-auth`](./key-auth.md), you can easily replace it with other authentication Plugins.

Create a Consumer `john`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "john"
  }'
```

Create `key-auth` credential for the consumer:

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

Create a second Consumer `jane`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "jane"
  }'
```

Create `key-auth` credential for the consumer:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/jane/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-jane-key-auth",
    "plugins": {
      "key-auth": {
        "key": "jane-key"
      }
    }
  }'
```

Create a third Consumer `jimmy`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "jimmy"
  }'
```

Create `key-auth` credential for the consumer:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/jimmy/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-jimmy-key-auth",
    "plugins": {
      "key-auth": {
        "key": "jimmy-key"
      }
    }
  }'
```

Create a Route with the `workflow` and `key-auth` Plugins, with the desired rate limiting rules:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "workflow-route",
    "uri": "/anything",
    "plugins":{
      "key-auth": {},
      "workflow":{
        "rules":[
          {
            "actions": [
              [
                "limit-count",
                {
                  "count": 5,
                  "key": "consumer_john",
                  "key_type": "constant",
                  "rejected_code": 429,
                  "time_window": 30
                }
              ]
            ],
            "case": [
              [
                "consumer_name",
                "==",
                "john"
              ]
            ]
          },
          {
            "actions": [
              [
                "limit-count",
                {
                  "count": 3,
                  "key": "consumer_jane",
                  "key_type": "constant",
                  "rejected_code": 429,
                  "time_window": 30
                }
              ]
            ],
            "case": [
              [
                "consumer_name",
                "==",
                "jane"
              ]
            ]
          },
          {
            "actions": [
              [
                "limit-count",
                {
                  "count": 2,
                  "key": "$consumer_name",
                  "key_type": "var",
                  "rejected_code": 429,
                  "time_window": 30
                }
              ]
            ]
          }
        ]
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org": 1
      }
    }
  }'
```

To verify, send 6 consecutive requests with `john`'s key:

```shell
resp=$(seq 6 | xargs -I{} curl "http://127.0.0.1:9080/anything" -H 'apikey: john-key' -o /dev/null -s -w "%{http_code}\n") && \
  count_200=$(echo "$resp" | grep "200" | wc -l) && \
  count_429=$(echo "$resp" | grep "429" | wc -l) && \
  echo "200": $count_200, "429": $count_429
```

You should see the following response, showing that out of the 6 requests, 5 requests were successful (status code 200) while the others were rejected (status code 429).

```text
200:    5, 429:    1
```

Send 6 consecutive requests with `jane`'s key:

```shell
resp=$(seq 6 | xargs -I{} curl "http://127.0.0.1:9080/anything" -H 'apikey: jane-key' -o /dev/null -s -w "%{http_code}\n") && \
  count_200=$(echo "$resp" | grep "200" | wc -l) && \
  count_429=$(echo "$resp" | grep "429" | wc -l) && \
  echo "200": $count_200, "429": $count_429
```

You should see the following response, showing that out of the 6 requests, 3 requests were successful (status code 200) while the others were rejected (status code 429).

```text
200:    3, 429:    3
```

Send 3 consecutive requests with `jimmy`'s key:

```shell
resp=$(seq 3 | xargs -I{} curl "http://127.0.0.1:9080/anything" -H 'apikey: jimmy-key' -o /dev/null -s -w "%{http_code}\n") && \
  count_200=$(echo "$resp" | grep "200" | wc -l) && \
  count_429=$(echo "$resp" | grep "429" | wc -l) && \
  echo "200": $count_200, "429": $count_429
```

You should see the following response, showing that out of the 3 requests, 2 requests were successful (status code 200) while the others were rejected (status code 429).

```text
200:    2, 429:    1
```
