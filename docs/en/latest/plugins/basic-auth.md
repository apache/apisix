---
title: basic-auth
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - Basic Auth
  - basic-auth
description: The basic-auth Plugin adds basic access authentication for Consumers to authenticate themselves before being able to access Upstream resources.
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
  <link rel="canonical" href="https://docs.api7.ai/hub/basic-auth" />
</head>

## Description

The `basic-auth` Plugin adds [basic access authentication](https://en.wikipedia.org/wiki/Basic_access_authentication) for [Consumers](../terminology/consumer.md) to authenticate themselves before being able to access Upstream resources.

When a Consumer is successfully authenticated, APISIX adds additional headers, such as `X-Consumer-Username`, `X-Credential-Indentifier`, and other Consumer custom headers if configured, to the request, before proxying it to the Upstream service. The Upstream service will be able to differentiate between consumers and implement additional logics as needed. If any of these values is not available, the corresponding header will not be added.

## Attributes

For Consumer/Credentials:

| Name     | Type   | Required | Description                                                                                                            |
|----------|--------|----------|------------------------------------------------------------------------------------------------------------------------|
| username | string | True     | Unique basic auth username for a consumer. |
| password | string | True     | Basic auth password for the consumer.  |

NOTE: `encrypt_fields = {"password"}` is also defined in the schema, which means that the field will be stored encrypted in etcd. See [encrypted storage fields](../plugin-develop.md#encrypted-storage-fields).

For Route:

| Name             | Type    | Required | Default | Description                                                            |
|------------------|---------|----------|---------|------------------------------------------------------------------------|
| hide_credentials | boolean | False    | false   | If true, do not pass the authorization request header to Upstream services. |
| anonymous_consumer | boolean | False    | false | Anonymous Consumer name. If configured, allow anonymous users to bypass the authentication. |
| realm            | string  | False    | basic | The realm to include in the `WWW-Authenticate` header when authentication fails. |

## Examples

The examples below demonstrate how you can work with the `basic-auth` Plugin for different scenarios.

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Implement Basic Authentication on Route

The following example demonstrates how to implement basic authentication on a Route.

Create a Consumer `johndoe`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "johndoe"
  }'
```

Create `basic-auth` Credential for the consumer:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/johndoe/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-john-basic-auth",
    "plugins": {
      "basic-auth": {
        "username": "johndoe",
        "password": "john-key"
      }
    }
  }'
```

Create a Route with `basic-auth`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "basic-auth-route",
    "uri": "/anything",
    "plugins": {
      "basic-auth": {}
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```

#### Verify with a Valid Key

Send a request to with the valid key:

```shell
curl -i "http://127.0.0.1:9080/anything" -u johndoe:john-key
```

You should see an `HTTP/1.1 200 OK` response similar to the following:

```json
{
  "args": {},
  "headers": {
    "Accept": "*/*",
    "Apikey": "john-key",
    "Authorization": "Basic am9obmRvZTpqb2huLWtleQ==",
    "Host": "127.0.0.1",
    "User-Agent": "curl/8.6.0",
    "X-Amzn-Trace-Id": "Root=1-66e5107c-5bb3e24f2de5baf733aec1cc",
    "X-Consumer-Username": "john",
    "X-Credential-Indentifier": "cred-john-basic-auth",
    "X-Forwarded-Host": "127.0.0.1"
  },
  "origin": "192.168.65.1, 205.198.122.37",
  "url": "http://127.0.0.1/get"
}
```

#### Verify with an Invalid Key

Send a request with an invalid key:

```shell
curl -i "http://127.0.0.1:9080/anything" -u johndoe:invalid-key
```

You should see an `HTTP/1.1 401 Unauthorized` response with the following:

```text
{"message":"Invalid user authorization"}
```

#### Verify without a Key

Send a request to without a key:

```shell
curl -i "http://127.0.0.1:9080/anything"
```

You should see an `HTTP/1.1 401 Unauthorized` response with the following:

```text
{"message":"Missing authorization in request"}
```

### Hide Authentication Information From Upstream

The following example demonstrates how to prevent the key from being sent to the Upstream services by configuring `hide_credentials`. In APISIX, the authentication key is forwarded to the Upstream services by default, which might lead to security risks in some circumstances and you should consider updating `hide_credentials`.

Create a Consumer `johndoe`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "johndoe"
  }'
```

Create `basic-auth` Credential for the consumer:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/johndoe/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-john-basic-auth",
    "plugins": {
      "basic-auth": {
        "username": "johndoe",
        "password": "john-key"
      }
    }
  }'
```

#### Without Hiding Credentials

Create a Route with `basic-auth` and configure `hide_credentials` to `false`, which is the default configuration:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
-H "X-API-KEY: ${admin_key}" \
-d '{
  "id": "basic-auth-route",
  "uri": "/anything",
  "plugins": {
    "basic-auth": {
      "hide_credentials": false
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

Send a request with the valid key:

```shell
curl -i "http://127.0.0.1:9080/anything" -u johndoe:john-key
```

You should see an `HTTP/1.1 200 OK` response with the following:

```json
{
  "args": {},
  "data": "",
  "files": {},
  "form": {},
  "headers": {
    "Accept": "*/*",
    "Authorization": "Basic am9obmRvZTpqb2huLWtleQ==",
    "Host": "127.0.0.1",
    "User-Agent": "curl/8.6.0",
    "X-Amzn-Trace-Id": "Root=1-66cc2195-22bd5f401b13480e63c498c6",
    "X-Consumer-Username": "john",
    "X-Credential-Indentifier": "cred-john-basic-auth",
    "X-Forwarded-Host": "127.0.0.1"
  },
  "json": null,
  "method": "GET",
  "origin": "192.168.65.1, 43.228.226.23",
  "url": "http://127.0.0.1/anything"
}
```

Note that the credentials are visible to the Upstream service in base64-encoded format.

:::tip

You can also pass the base64-encoded credentials in the request using the `Authorization` header as such:

```shell
curl -i "http://127.0.0.1:9080/anything" -H "Authorization: Basic am9obmRvZTpqb2huLWtleQ=="
```

:::

#### Hide Credentials

Update the plugin's `hide_credentials` to `true`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/basic-auth-route" -X PATCH \
-H "X-API-KEY: ${admin_key}" \
-d '{
  "plugins": {
    "basic-auth": {
      "hide_credentials": true
    }
  }
}'
```

Send a request with the valid key:

```shell
curl -i "http://127.0.0.1:9080/anything" -u johndoe:john-key
```

You should see an `HTTP/1.1 200 OK` response with the following:

```json
{
  "args": {},
  "data": "",
  "files": {},
  "form": {},
  "headers": {
    "Accept": "*/*",
    "Host": "127.0.0.1",
    "User-Agent": "curl/8.6.0",
    "X-Amzn-Trace-Id": "Root=1-66cc21a7-4f6ac87946e25f325167d53a",
    "X-Consumer-Username": "john",
    "X-Credential-Indentifier": "cred-john-basic-auth",
    "X-Forwarded-Host": "127.0.0.1"
  },
  "json": null,
  "method": "GET",
  "origin": "192.168.65.1, 43.228.226.23",
  "url": "http://127.0.0.1/anything"
}
```

Note that the credentials are no longer visible to the Upstream service.

### Add Consumer Custom ID to Header

The following example demonstrates how you can attach a Consumer custom ID to authenticated request in the `Consumer-Custom-Id` header, which can be used to implement additional logics as needed.

Create a Consumer `johndoe` with a custom ID label:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "johndoe",
    "labels": {
      "custom_id": "495aec6a"
    }
  }'
```

Create `basic-auth` Credential for the consumer:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/johndoe/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-john-basic-auth",
    "plugins": {
      "basic-auth": {
        "username": "johndoe",
        "password": "john-key"
      }
    }
  }'
```

Create a Route with `basic-auth`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "basic-auth-route",
    "uri": "/anything",
    "plugins": {
      "basic-auth": {}
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```

To verify, send a request to the Route with the valid key:

```shell
curl -i "http://127.0.0.1:9080/anything" -u johndoe:john-key
```

You should see an `HTTP/1.1 200 OK` response with the `X-Consumer-Custom-Id` similar to the following:

```json
{
  "args": {},
  "data": "",
  "files": {},
  "form": {},
  "headers": {
    "Accept": "*/*",
    "Authorization": "Basic am9obmRvZTpqb2huLWtleQ==",
    "Host": "127.0.0.1",
    "User-Agent": "curl/8.6.0",
    "X-Amzn-Trace-Id": "Root=1-66ea8d64-33df89052ae198a706e18c2a",
    "X-Consumer-Username": "johndoe",
    "X-Credential-Identifier": "cred-john-basic-auth",
    "X-Consumer-Custom-Id": "495aec6a",
    "X-Forwarded-Host": "127.0.0.1"
  },
  "json": null,
  "method": "GET",
  "origin": "192.168.65.1, 205.198.122.37",
  "url": "http://127.0.0.1/anything"
}
```

### Rate Limit with Anonymous Consumer

The following example demonstrates how you can configure different rate limiting policies by regular and anonymous consumers, where the anonymous Consumer does not need to authenticate and has less quotas.

Create a regular Consumer `johndoe` and configure the `limit-count` Plugin to allow for a quota of 3 within a 30-second window:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "johndoe",
    "plugins": {
      "limit-count": {
        "count": 3,
        "time_window": 30,
        "rejected_code": 429
      }
    }
  }'
```

Create the `basic-auth` Credential for the Consumer `johndoe`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/johndoe/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-john-basic-auth",
    "plugins": {
      "basic-auth": {
        "username": "johndoe",
        "password": "john-key"
      }
    }
  }'
```

Create an anonymous user `anonymous` and configure the `limit-count` Plugin to allow for a quota of 1 within a 30-second window:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "anonymous",
    "plugins": {
      "limit-count": {
        "count": 1,
        "time_window": 30,
        "rejected_code": 429
      }
    }
  }'
```

Create a Route and configure the `basic-auth` Plugin to accept anonymous Consumer `anonymous` from bypassing the authentication:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "basic-auth-route",
    "uri": "/anything",
    "plugins": {
      "basic-auth": {
        "anonymous_consumer": "anonymous"
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

To verify, send five consecutive requests with `john`'s key:

```shell
resp=$(seq 5 | xargs -I{} curl "http://127.0.0.1:9080/anything" -u johndoe:john-key -o /dev/null -s -w "%{http_code}\n") && \
  count_200=$(echo "$resp" | grep "200" | wc -l) && \
  count_429=$(echo "$resp" | grep "429" | wc -l) && \
  echo "200": $count_200, "429": $count_429
```

You should see the following response, showing that out of the 5 requests, 3 requests were successful (status code 200) while the others were rejected (status code 429).

```text
200:    3, 429:    2
```

Send five anonymous requests:

```shell
resp=$(seq 5 | xargs -I{} curl "http://127.0.0.1:9080/anything" -o /dev/null -s -w "%{http_code}\n") && \
  count_200=$(echo "$resp" | grep "200" | wc -l) && \
  count_429=$(echo "$resp" | grep "429" | wc -l) && \
  echo "200": $count_200, "429": $count_429
```

You should see the following response, showing that only one request was successful:

```text
200:    1, 429:    4
```
