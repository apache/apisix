---
title: traffic-split
keywords:
  - Apache APISIX
  - API Gateway
  - Traffic Split
  - Blue-green Deployment
  - Canary Deployment
description: The traffic-split Plugin directs traffic to various Upstream services based on conditions and/or weights. It provides a dynamic and flexible approach to implement release strategies and manage traffic.
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
  <link rel="canonical" href="https://docs.api7.ai/hub/traffic-split" />
</head>

## Description

The `traffic-split` Plugin directs traffic to various Upstream services based on conditions and/or weights. It provides a dynamic and flexible approach to implement release strategies and manage traffic.

:::note

The traffic ratio between Upstream services may be less accurate since round robin algorithm is used to direct traffic (especially when the state is reset).

:::

## Attributes

| Name                           | Type           | Required | Default    | Valid values                | Description                                                                                                                                                                                                                                                                                                                                               |
|--------------------------------|----------------|----------|------------|-----------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| rules.match                    | array[object]  | False    |            |                             | An array of one or more pairs of matching conditions and actions to be executed.     |
| rules.match                    | array[object]  | False    |            |                             | Rules to match for conditional traffic split.           |
| rules.match.vars               | array[array]   | False    |            |                             | An array of one or more matching conditions in the form of [lua-resty-expr](https://github.com/api7/lua-resty-expr#operator-list) to conditionally execute the plugin. |
| rules.weighted_upstreams       | array[object]  | False    |            |                             | List of Upstream configurations.    |
| rules.weighted_upstreams.upstream_id | string/integer | False    |            |                             | ID of the configured Upstream object.    |
| rules.weighted_upstreams.weight      | integer        | False    | weight = 1 |                             | Weight for each upstream.  |
| rules.weighted_upstreams.upstream    | object         | False    |            |                             | Configuration of the upstream. Certain configuration options Upstream are not supported here. These fields are `service_name`, `discovery_type`, `checks`, `retries`, `retry_timeout`, `desc`, and `labels`. As a workaround, you can create an Upstream object and configure it in `upstream_id`.    |
| rules.weighted_upstreams.upstream.type                  | array           | False    | roundrobin | [roundrobin, chash]         | Algorithm for traffic splitting. `roundrobin` for weighted round robin and `chash` for consistent hashing.        |
| rules.weighted_upstreams.upstream.hash_on               | array           | False    | vars       |                             | Used when `type` is `chash`. Support hashing on [NGINX  variables](https://nginx.org/en/docs/varindex.html), headers, cookie, Consumer, or a combination of [NGINX  variables](https://nginx.org/en/docs/varindex.html).         |
| rules.weighted_upstreams.upstream.key                   | string         | False    |            |                             | Used when `type` is `chash`. When `hash_on` is set to `header` or `cookie`, `key` is required. When `hash_on` is set to `consumer`, `key` is not required as the Consumer name will be used as the key automatically.          |
| rules.weighted_upstreams.upstream.nodes                 | object         | False    |            |                             | Addresses of the Upstream nodes.   |
| rules.weighted_upstreams.upstream.timeout               | object         | False    | 15         |                             |  Timeout in seconds for connecting, sending and receiving messages.                |
| rules.weighted_upstreams.upstream.pass_host             | array           | False    | "pass"     | ["pass", "node", "rewrite"] | Mode deciding how the host name is passed. `pass` passes the client's host name to the upstream. `node` passes the host configured in the node of the upstream. `rewrite` passes the value configured in `upstream_host`.             |
| rules.weighted_upstreams.upstream.name                  | string         | False    |            |                             |  Identifier for the Upstream for specifying service name, usage scenarios, and so on.        |
| rules.weighted_upstreams.upstream.upstream_host         | string         | False    |            |                             | Used when `pass_host` is `rewrite`. Host name of the upstream.         |

## Examples

The examples below show different use cases for using the `traffic-split` Plugin.

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Implement Canary Release

The following example demonstrates how to implement canary release with this Plugin.

A Canary release is a gradual deployment in which an increasing percentage of traffic is directed to a new release, allowing for a controlled and monitored rollout. This method ensures that any potential issues or bugs in the new release can be identified and addressed early on, before fully redirecting all traffic.

Create a Route and configure `traffic-split` Plugin with the following rules:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "uri": "/headers",
    "id": "traffic-split-route",
    "plugins": {
      "traffic-split": {
        "rules": [
          {
            "weighted_upstreams": [
              {
                "upstream": {
                  "type": "roundrobin",
                  "scheme": "https",
                  "pass_host": "node",
                  "nodes": {
                    "httpbin.org:443":1
                  }
                },
                "weight": 3
              },
              {
                "weight": 2
              }
            ]
          }
        ]
      }
    },
    "upstream": {
      "type": "roundrobin",
      "scheme": "https",
      "pass_host": "node",
      "nodes": {
        "mock.api7.ai:443":1
      }
    }
  }'
```

The proportion of traffic to each Upstream is determined by the weight of the Upstream relative to the total weight of all upstreams. Here, the total weight is calculated as: 3 + 2 = 5.

Therefore, 60% of the traffic are to be forwarded to `httpbin.org` and the other 40% of the traffic are to be forwarded to `mock.api7.ai`.

Send 10 consecutive requests to the Route to verify:

```shell
resp=$(seq 10 | xargs -I{} curl "http://127.0.0.1:9080/headers" -sL) && \
  count_httpbin=$(echo "$resp" | grep "httpbin.org" | wc -l) && \
  count_mockapi7=$(echo "$resp" | grep "mock.api7.ai" | wc -l) && \
  echo httpbin.org: $count_httpbin, mock.api7.ai: $count_mockapi7
```

You should see a response similar to the following:

```text
httpbin.org: 6, mock.api7.ai: 4
```

Adjust the Upstream weights accordingly to complete the canary release.

### Implement Blue-Green Deployment

The following example demonstrates how to implement blue-green deployment with this Plugin.

Blue-green deployment is a deployment strategy that involves maintaining two identical environments: the _blue_ and the _green_. The blue environment refers to the current production deployment and the green environment refers to the new deployment. Once the green environment is tested to be ready for production, traffic will be routed to the green environment, making it the new production deployment.

Create a Route and configure `traffic-split` Plugin to execute the Plugin to redirect traffic only when the request contains a header `release: new_release`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "uri": "/headers",
    "id": "traffic-split-route",
    "plugins": {
      "traffic-split": {
        "rules": [
          {
            "match": [
              {
                "vars": [
                  ["http_release","==","new_release"]
                ]
              }
            ],
            "weighted_upstreams": [
              {
                "upstream": {
                  "type": "roundrobin",
                  "scheme": "https",
                  "pass_host": "node",
                  "nodes": {
                    "httpbin.org:443":1
                  }
                }
              }
            ]
          }
        ]
      }
    },
    "upstream": {
      "type": "roundrobin",
      "scheme": "https",
      "pass_host": "node",
      "nodes": {
        "mock.api7.ai:443":1
      }
    }
  }'
```

Send a request to the Route with the `release` header:

```shell
curl "http://127.0.0.1:9080/headers" -H 'release: new_release'
```

You should see a response similar to the following:

```json
{
  "headers": {
    "Accept": "*/*",
    "Host": "httpbin.org",
    ...
  }
}
```

Send a request to the Route without any additional header:

```shell
curl "http://127.0.0.1:9080/headers"
```

You should see a response similar to the following:

```json
{
  "headers": {
    "accept": "*/*",
    "host": "mock.api7.ai",
    ...
  }
}
```

### Define Matching Condition for POST Request With APISIX Expressions

The following example demonstrates how to use [lua-resty-expr](https://github.com/api7/lua-resty-expr#operator-list) in rules to conditionally execute the Plugin when certain condition of a POST request is satisfied.

Create a Route and configure `traffic-split` Plugin with the following rules:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "uri": "/post",
    "methods": ["POST"],
    "id": "traffic-split-route",
    "plugins": {
      "traffic-split": {
        "rules": [
          {
            "match": [
              {
                "vars": [
                  ["post_arg_id", "==", "1"]
                ]
              }
            ],
            "weighted_upstreams": [
              {
                "upstream": {
                  "type": "roundrobin",
                  "scheme": "https",
                  "pass_host": "node",
                  "nodes": {
                    "httpbin.org:443":1
                  }
                }
              }
            ]
          }
        ]
      }
    },
    "upstream": {
      "type": "roundrobin",
      "scheme": "https",
      "pass_host": "node",
      "nodes": {
        "mock.api7.ai:443":1
      }
    }
  }'
```

Send a POST request with body `id=1`:

```shell
curl "http://127.0.0.1:9080/post" -X POST \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d 'id=1'
```

You should see a response similar to the following:

```json
{
  "args": {},
  "data": "",
  "files": {},
  "form": {
    "id": "1"
  },
  "headers": {
    "Accept": "*/*",
    "Content-Length": "4",
    "Content-Type": "application/x-www-form-urlencoded",
    "Host": "httpbin.org",
    ...
  },
  ...
}
```

Send a POST request without `id=1` in the body:

```shell
curl "http://127.0.0.1:9080/post" -X POST \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d 'random=string'
```

You should see that the request was forwarded to `mock.api7.ai`.

### Define AND Matching Conditions With APISIX Expressions

The following example demonstrates how to use [lua-resty-expr](https://github.com/api7/lua-resty-expr#operator-list) in rules to conditionally execute the Plugin when multiple conditions are satisfied.

Create a Route and configure `traffic-split` Plugin to redirect traffic only when all three conditions are satisfied:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "uri": "/headers",
    "id": "traffic-split-route",
    "plugins": {
      "traffic-split": {
        "rules": [
          {
            "match": [
              {
                "vars": [
                  ["arg_name","==","jack"],
                  ["http_user-id",">","23"],
                  ["http_apisix-key","~~","[a-z]+"]
                ]
              }
            ],
            "weighted_upstreams": [
              {
                "upstream": {
                  "type": "roundrobin",
                  "scheme": "https",
                  "pass_host": "node",
                  "nodes": {
                    "httpbin.org:443":1
                  }
                },
                "weight": 3
              },
              {
                "weight": 2
              }
            ]
          }
        ]
      }
    },
    "upstream": {
      "type": "roundrobin",
      "scheme": "https",
      "pass_host": "node",
      "nodes": {
        "mock.api7.ai:443":1
      }
    }
  }'
```

If conditions are satisfied, 60% of the traffic should be directed to `httpbin.org` and the other 40% should be directed to `mock.api7.ai`. If conditions are not satisfied, all traffic should be directed to `mock.api7.ai`.

Send 10 consecutive requests that satisfy all conditions to verify:

```shell
resp=$(seq 10 | xargs -I{} curl "http://127.0.0.1:9080/headers?name=jack" -H 'user-id: 30' -H 'apisix-key: helloapisix' -sL) && \
  count_httpbin=$(echo "$resp" | grep "httpbin.org" | wc -l) && \
  count_mockapi7=$(echo "$resp" | grep "mock.api7.ai" | wc -l) && \
  echo httpbin.org: $count_httpbin, mock.api7.ai: $count_mockapi7
```

You should see a response similar to the following:

```text
httpbin.org: 6, mock.api7.ai: 4
```

Send 10 consecutive requests that do not satisfy the conditions to verify:

```shell
resp=$(seq 10 | xargs -I{} curl "http://127.0.0.1:9080/headers?name=random" -sL) && \
  count_httpbin=$(echo "$resp" | grep "httpbin.org" | wc -l) && \
  count_mockapi7=$(echo "$resp" | grep "mock.api7.ai" | wc -l) && \
  echo httpbin.org: $count_httpbin, mock.api7.ai: $count_mockapi7
```

You should see a response similar to the following:

```text
httpbin.org: 0, mock.api7.ai: 10
```

### Define OR Matching Conditions With APISIX Expressions

The following example demonstrates how to use [lua-resty-expr](https://github.com/api7/lua-resty-expr#operator-list) in rules to conditionally execute the Plugin when either set of the condition is satisfied.

Create a Route and configure `traffic-split` Plugin to redirect traffic when either set of the configured conditions are satisfied:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "uri": "/headers",
    "id": "traffic-split-route",
    "plugins": {
      "traffic-split": {
        "rules": [
          {
            "match": [
              {
                "vars": [
                  ["arg_name","==","jack"],
                  ["http_user-id",">","23"],
                  ["http_apisix-key","~~","[a-z]+"]
                ]
              },
              {
                "vars": [
                  ["arg_name2","==","rose"],
                  ["http_user-id2","!",">","33"],
                  ["http_apisix-key2","~~","[a-z]+"]
                ]
              }
            ],
            "weighted_upstreams": [
              {
                "upstream": {
                  "type": "roundrobin",
                  "scheme": "https",
                  "pass_host": "node",
                  "nodes": {
                    "httpbin.org:443":1
                  }
                },
                "weight": 3
              },
              {
                "weight": 2
              }
            ]
          }
        ]
      }
    },
    "upstream": {
      "type": "roundrobin",
      "scheme": "https",
      "pass_host": "node",
      "nodes": {
        "mock.api7.ai:443":1
      }
    }
  }'
```

Alternatively, you can also use the OR operator in the [lua-resty-expr](https://github.com/api7/lua-resty-expr#operator-list) for these conditions.

If conditions are satisfied, 60% of the traffic should be directed to `httpbin.org` and the other 40% should be directed to `mock.api7.ai`. If conditions are not satisfied, all traffic should be directed to `mock.api7.ai`.

Send 10 consecutive requests that satisfy the second set of conditions to verify:

```shell
resp=$(seq 10 | xargs -I{} curl "http://127.0.0.1:9080/headers?name2=rose" -H 'user-id:30' -H 'apisix-key2: helloapisix' -sL) && \
  count_httpbin=$(echo "$resp" | grep "httpbin.org" | wc -l) && \
  count_mockapi7=$(echo "$resp" | grep "mock.api7.ai" | wc -l) && \
  echo httpbin.org: $count_httpbin, mock.api7.ai: $count_mockapi7
```

You should see a response similar to the following:

```json
httpbin.org: 6, mock.api7.ai: 4
```

Send 10 consecutive requests that do not satisfy any set of conditions to verify:

```shell
resp=$(seq 10 | xargs -I{} curl "http://127.0.0.1:9080/headers?name=random" -sL) && \
  count_httpbin=$(echo "$resp" | grep "httpbin.org" | wc -l) && \
  count_mockapi7=$(echo "$resp" | grep "mock.api7.ai" | wc -l) && \
  echo httpbin.org: $count_httpbin, mock.api7.ai: $count_mockapi7
```

You should see a response similar to the following:

```json
httpbin.org: 0, mock.api7.ai: 10
```

### Configure Different Rules for Different Upstreams

The following example demonstrates how to set one-to-one mapping between rule sets and upstreams.

Create a Route and configure `traffic-split` Plugin with the following matching rules to redirect traffic when the request contains a header `x-api-id: 1` or `x-api-id: 2`, to the corresponding Upstream service:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "uri": "/headers",
    "id": "traffic-split-route",
    "plugins": {
      "traffic-split": {
        "rules": [
          {
            "match": [
              {
                "vars": [
                  ["http_x-api-id","==","1"]
                ]
              }
            ],
            "weighted_upstreams": [
              {
                "upstream": {
                  "type": "roundrobin",
                  "scheme": "https",
                  "pass_host": "node",
                  "nodes": {
                    "httpbin.org:443":1
                  }
                },
                "weight": 1
              }
            ]
          },
          {
            "match": [
              {
                "vars": [
                  ["http_x-api-id","==","2"]
                ]
              }
            ],
            "weighted_upstreams": [
              {
                "upstream": {
                  "type": "roundrobin",
                  "scheme": "https",
                  "pass_host": "node",
                  "nodes": {
                    "mock.api7.ai:443":1
                  }
                },
                "weight": 1
              }
            ]
          }
        ]
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "postman-echo.com:443": 1
      },
      "scheme": "https",
      "pass_host": "node"
    }
  }'
```

Send a request with header `x-api-id: 1`:

```shell
curl "http://127.0.0.1:9080/headers" -H 'x-api-id: 1'
```

You should see an `HTTP/1.1 200 OK` response similar to the following:

```json
{
  "headers": {
    "Accept": "*/*",
    "Host": "httpbin.org",
    ...
  }
}
```

Send a request with header `x-api-id: 2`:

```shell
curl "http://127.0.0.1:9080/headers" -H 'x-api-id: 2'
```

You should see an `HTTP/1.1 200 OK` response similar to the following:

```json
{
  "headers": {
    "accept": "*/*",
    "host": "mock.api7.ai",
    ...
  }
}
```

Send a request without any additional header:

```shell
curl "http://127.0.0.1:9080/headers"
```

You should see a response similar to the following:

```json
{
  "headers": {
    "accept": "*/*",
    "host": "postman-echo.com",
    ...
  }
}
```
