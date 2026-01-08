---
title: key-auth
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - Key Auth
  - key-auth
description: The key-auth Plugin supports the use of an authentication key as a mechanism for clients to authenticate themselves before accessing Upstream resources.
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
    <link rel="canonical" href="https://docs.api7.ai/hub/key-auth" />
</head>

## Description

The `key-auth` Plugin supports the use of an authentication key as a mechanism for clients to authenticate themselves before accessing Upstream resources.

To use the plugin, you would configure authentication keys on [Consumers](../terminology/consumer.md) and enable the Plugin on routes or services. The key can be included in the request URL query string or request header. APISIX will then verify the key to determine if a request should be allowed or denied to access Upstream resources.

When a Consumer is successfully authenticated, APISIX adds additional headers, such as `X-Consumer-Username`, `X-Credential-Indentifier`, and other Consumer custom headers if configured, to the request, before proxying it to the Upstream service. The Upstream service will be able to differentiate between consumers and implement additional logics as needed. If any of these values is not available, the corresponding header will not be added.

## Attributes

For Consumer/Credential:

| Name | Type   | Required | Description                |
|------|--------|-------------|----------------------------|
| key  | string | True    | Unique key for a Consumer. This field supports saving the value in Secret Manager using the [APISIX Secret](../terminology/secret.md) resource. |

NOTE: `encrypt_fields = {"key"}` is also defined in the schema, which means that the field will be stored encrypted in etcd. See [encrypted storage fields](../plugin-develop.md#encrypted-storage-fields).

For Route:

| Name   | Type   | Required | Default | Description                                                                                                                                                                                                                                                                   |
|--------|--------|-------------|-------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| header | string | False    | apikey | The header to get the key from.                                                                                                                                                                                                                                               |
| query  | string | False    | apikey  | The query string to get the key from. Lower priority than header.                                                                                                                                                                                                             |
| hide_credentials   | boolean | False    | false  | If true, do not pass the header or query string with key to Upstream services.  |
| anonymous_consumer | string  | False    | false  | Anonymous Consumer name. If configured, allow anonymous users to bypass the authentication.  |
| realm              | string  | False    | key    | The realm to include in the `WWW-Authenticate` header when authentication fails. |

## Examples

The examples below demonstrate how you can work with the `key-auth` Plugin for different scenarios.

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Implement Key Authentication on Route

The following example demonstrates how to implement key authentications on a Route and include the key in the request header.

Create a Consumer `jack`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "jack"
  }'
```

Create `key-auth` Credential for the Consumer:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/jack/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-jack-key-auth",
    "plugins": {
      "key-auth": {
        "key": "jack-key"
      }
    }
  }'
```

Create a Route with `key-auth`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "key-auth-route",
    "uri": "/anything",
    "plugins": {
      "key-auth": {}
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
curl -i "http://127.0.0.1:9080/anything" -H 'apikey: jack-key'
```

You should receive an `HTTP/1.1 200 OK` response.

#### Verify with an Invalid Key

Send a request with an invalid key:

```shell
curl -i "http://127.0.0.1:9080/anything" -H 'apikey: wrong-key'
```

You should see an `HTTP/1.1 401 Unauthorized` response with the following:

```text
{"message":"Invalid API key in request"}
```

#### Verify without a Key

Send a request to without a key:

```shell
curl -i "http://127.0.0.1:9080/anything"
```

You should see an `HTTP/1.1 401 Unauthorized` response with the following:

```text
{"message":"Missing API key found in request"}
```

### Hide Authentication Information From Upstream

The following example demonstrates how to prevent the key from being sent to the Upstream services by configuring `hide_credentials`. By default, the authentication key is forwarded to the Upstream services, which might lead to security risks in some circumstances.

Create a Consumer `jack`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "jack"
  }'
```

Create `key-auth` Credential for the Consumer:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/jack/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-jack-key-auth",
    "plugins": {
      "key-auth": {
        "key": "jack-key"
      }
    }
  }'
```

#### Without Hiding Credentials

Create a Route with `key-auth` and configure `hide_credentials` to `false`, which is the default configuration:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
-H "X-API-KEY: ${admin_key}" \
-d '{
  "id": "key-auth-route",
  "uri": "/anything",
  "plugins": {
    "key-auth": {
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
curl -i "http://127.0.0.1:9080/anything?apikey=jack-key"
```

You should see an `HTTP/1.1 200 OK` response with the following:

```json
{
  "args": {
    "auth": "jack-key"
  },
  "data": "",
  "files": {},
  "form": {},
  "headers": {
    "Accept": "*/*",
    "Host": "127.0.0.1",
    "User-Agent": "curl/8.2.1",
    "X-Consumer-Username": "jack",
    "X-Credential-Identifier": "cred-jack-key-auth",
    "X-Amzn-Trace-Id": "Root=1-6502d8a5-2194962a67aa21dd33f94bb2",
    "X-Forwarded-Host": "127.0.0.1"
  },
  "json": null,
  "method": "GET",
  "origin": "127.0.0.1, 103.248.35.179",
  "url": "http://127.0.0.1/anything?apikey=jack-key"
}
```

Note that the Credential `jack-key` is visible to the Upstream service.

#### Hide Credentials

Update the plugin's `hide_credentials` to `true`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/key-auth-route" -X PATCH \
-H "X-API-KEY: ${admin_key}" \
-d '{
  "plugins": {
    "key-auth": {
      "hide_credentials": true
    }
  }
}'
```

Send a request with the valid key:

```shell
curl -i "http://127.0.0.1:9080/anything?apikey=jack-key"
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
    "User-Agent": "curl/8.2.1",
    "X-Consumer-Username": "jack",
    "X-Credential-Identifier": "cred-jack-key-auth",
    "X-Amzn-Trace-Id": "Root=1-6502d85c-16f34dbb5629a5960183e803",
    "X-Forwarded-Host": "127.0.0.1"
  },
  "json": null,
  "method": "GET",
  "origin": "127.0.0.1, 103.248.35.179",
  "url": "http://127.0.0.1/anything"
}
```

Note that the Credential `jack-key` is no longer visible to the Upstream service.

### Demonstrate Priority of Keys in Header and Query

The following example demonstrates how to implement key authentication by consumers on a Route and customize the URL parameter that should include the key. The example also shows that when the API key is configured in both the header and the query string, the request header has a higher priority.

Create a Consumer `jack`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "jack"
  }'
```

Create `key-auth` Credential for the Consumer:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/jack/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-jack-key-auth",
    "plugins": {
      "key-auth": {
        "key": "jack-key"
      }
    }
  }'
```

Create a Route with `key-auth`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
-H "X-API-KEY: ${admin_key}" \
-d '{
  "id": "key-auth-route",
  "uri": "/anything",
  "plugins": {
    "key-auth": {
      "query": "auth"
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

#### Verify with a Valid Key

Send a request to with the valid key:

```shell
curl -i "http://127.0.0.1:9080/anything?auth=jack-key"
```

You should receive an `HTTP/1.1 200 OK` response.

#### Verify with an Invalid Key

Send a request with an invalid key:

```shell
curl -i "http://127.0.0.1:9080/anything?auth=wrong-key"
```

You should see an `HTTP/1.1 401 Unauthorized` response with the following:

```text
{"message":"Invalid API key in request"}
```

#### Verify with a Valid Key in Query String

However, if you include the valid key in header with the invalid key still in the URL query string:

```shell
curl -i "http://127.0.0.1:9080/anything?auth=wrong-key" -H 'apikey: jack-key'
```

You should see an `HTTP/1.1 200 OK` response. This shows that the key included in the header always has a higher priority.

### Add Consumer Custom ID to Header

The following example demonstrates how you can attach a Consumer custom ID to authenticated request in the `Consumer-Custom-Id` header, which can be used to implement additional logics as needed.

Create a Consumer `jack` with a custom ID label:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "jack",
    "labels": {
      "custom_id": "495aec6a"
    }
  }'
```

Create `key-auth` Credential for the Consumer:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/jack/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-jack-key-auth",
    "plugins": {
      "key-auth": {
        "key": "jack-key"
      }
    }
  }'
```

Create a Route with `key-auth`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "key-auth-route",
    "uri": "/anything",
    "plugins": {
      "key-auth": {}
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
curl -i "http://127.0.0.1:9080/anything?auth=jack-key"
```

You should see an `HTTP/1.1 200 OK` response similar to the following:

```json
{
  "args": {
    "auth": "jack-key"
  },
  "data": "",
  "files": {},
  "form": {},
  "headers": {
    "Accept": "*/*",
    "Host": "127.0.0.1",
    "User-Agent": "curl/8.6.0",
    "X-Amzn-Trace-Id": "Root=1-66ea8d64-33df89052ae198a706e18c2a",
    "X-Consumer-Username": "jack",
    "X-Credential-Identifier": "cred-jack-key-auth",
    "X-Consumer-Custom-Id": "495aec6a",
    "X-Forwarded-Host": "127.0.0.1"
  },
  "json": null,
  "method": "GET",
  "origin": "192.168.65.1, 205.198.122.37",
  "url": "http://127.0.0.1/anything?apikey=jack-key"
}
```

### Rate Limit with Anonymous Consumer

The following example demonstrates how you can configure different rate limiting policies by regular and anonymous consumers, where the anonymous Consumer does not need to authenticate and has less quotas.

Create a regular Consumer `jack` and configure the `limit-count` Plugin to allow for a quota of 3 within a 30-second window:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "jack",
    "plugins": {
      "limit-count": {
        "count": 3,
        "time_window": 30,
        "rejected_code": 429
      }
    }
  }'
```

Create the `key-auth` Credential for the Consumer `jack`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/jack/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-jack-key-auth",
    "plugins": {
      "key-auth": {
        "key": "jack-key"
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

Create a Route and configure the `key-auth` Plugin to accept anonymous Consumer `anonymous` from bypassing the authentication:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "key-auth-route",
    "uri": "/anything",
    "plugins": {
      "key-auth": {
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

To verify, send five consecutive requests with `jack`'s key:

```shell
resp=$(seq 5 | xargs -I{} curl "http://127.0.0.1:9080/anything" -H 'apikey: jack-key' -o /dev/null -s -w "%{http_code}\n") && \
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
