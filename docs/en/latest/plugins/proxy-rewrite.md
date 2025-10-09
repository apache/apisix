---
title: proxy-rewrite
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - Proxy Rewrite
  - proxy-rewrite
description: The proxy-rewrite Plugin offers options to rewrite requests that APISIX forwards to Upstream services. With this plugin, you can modify the HTTP methods, request destination Upstream addresses, request headers, and more.
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
  <link rel="canonical" href="https://docs.api7.ai/hub/proxy-rewrite" />
</head>

## Description

The `proxy-rewrite` Plugin offers options to rewrite requests that APISIX forwards to Upstream services. With this plugin, you can modify the HTTP methods, request destination Upstream addresses, request headers, and more.

## Attributes

| Name                        | Type          | Required | Default | Valid values                                                                                                                           | Description                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
|-----------------------------|---------------|----------|---------|----------------------------------------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| uri                         | string        | False    |         |                                                                                                                                        |  New Upstream URI path. Value supports [NGINX variables](https://nginx.org/en/docs/http/ngx_http_core_module.html). For example, `$arg_name`.                                                                                                                                                                                                                                                                                                                       |
| method                      | string        | False    |         | ["GET", "POST", "PUT", "HEAD", "DELETE", "OPTIONS","MKCOL", "COPY", "MOVE", "PROPFIND", "PROPFIND","LOCK", "UNLOCK", "PATCH", "TRACE"] | HTTP method to rewrite requests to use.                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| regex_uri                   | array[string] | False    |         |                                                                                                                                        | Regular expressions used to match the URI path from client requests and compose a new Upstream URI path. When both `uri` and `regex_uri` are configured, `uri` has a higher priority. The array should contain one or more **key-value pairs**, with the key being the regular expression to match URI against and value being the new Upstream URI path. For example, with `["^/iresty/(. *)/(. *)", "/$1-$2", ^/theothers/*", "/theothers"]`, if a request is originally sent to `/iresty/hello/world`, the Plugin will rewrite the Upstream URI path to `/iresty/hello-world`; if a request is originally sent to `/theothers/hello/world`, the Plugin will rewrite the Upstream URI path to `/theothers`. |
| host                        | string        | False    |         |                                                                                                                                        | Set [`Host`](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Host) request header.                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| headers                     | object        | False    |         |                                                                                                                                   |   Header actions to be executed. Can be set to objects of action verbs `add`, `remove`, and/or `set`; or an object consisting of headers to be `set`. When multiple action verbs are configured, actions are executed in the order of `add`, `remove`, and `set`.                |
| headers.add     | object   | False     |        |                 | Headers to append to requests. If a header already present in the request, the header value will be appended. Header value could be set to a constant, one or more [NGINX variables](https://nginx.org/en/docs/http/ngx_http_core_module.html), or the matched result of `regex_uri` using variables such as `$1-$2-$3`.                                                                                              |
| headers.set     | object  | False     |        |                 | Headers to set to requests. If a header already present in the request, the header value will be overwritten. Header value could be set to a constant, one or more [NGINX variables](https://nginx.org/en/docs/http/ngx_http_core_module.html), or the matched result of `regex_uri` using variables such as `$1-$2-$3`. Should not be used to set `Host`.                                                                                       |
| headers.remove  | array[string]   | False     |        |                 | Headers to remove from requests.
| use_real_request_uri_unsafe | boolean       | False    | false   |                                                                                                                                        | If true, bypass URI normalization and allow for the full original request URI. Enabling this option is considered unsafe.         |

## Examples

The examples below demonstrate how you can configure `proxy-rewrite` on a Route in different scenarios.

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Rewrite Host Header

The following example demonstrates how you can modify the `Host` header in a request. Note that you should not use `headers.set` to set the `Host` header.

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "proxy-rewrite-route",
    "methods": ["GET"],
    "uri": "/headers",
    "plugins": {
      "proxy-rewrite": {
        "host": "myapisix.demo"
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

Send a request to `/headers` to check all the request headers sent to upstream:

```shell
curl "http://127.0.0.1:9080/headers"
```

You should see a response similar to the following:

```text
{
  "headers": {
    "Accept": "*/*",
    "Host": "myapisix.demo",
    "User-Agent": "curl/8.2.1",
    "X-Amzn-Trace-Id": "Root=1-64fef198-29da0970383150175bd2d76d",
    "X-Forwarded-Host": "127.0.0.1"
  }
}
```

### Rewrite URI And Set Headers

The following example demonstrates how you can rewrite the request Upstream URI and set additional header values. If the same headers present in the client request, the corresponding header values set in the Plugin will overwrite the values present in the client request.

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "proxy-rewrite-route",
    "methods": ["GET"],
    "uri": "/",
    "plugins": {
      "proxy-rewrite": {
        "uri": "/anything",
        "headers": {
          "set": {
            "X-Api-Version": "v1",
            "X-Api-Engine": "apisix"
          }
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

Send a request to verify:

```shell
curl "http://127.0.0.1:9080/" -H '"X-Api-Version": "v2"'
```

You should see a response similar to the following:

```text
{
  "args": {},
  "data": "",
  "files": {},
  "form": {},
  "headers": {
    "Accept": "*/*",
    "Host": "httpbin.org",
    "User-Agent": "curl/8.2.1",
    "X-Amzn-Trace-Id": "Root=1-64fed73a-59cd3bd640d76ab16c97f1f1",
    "X-Api-Engine": "apisix",
    "X-Api-Version": "v1",
    "X-Forwarded-Host": "127.0.0.1"
  },
  "json": null,
  "method": "GET",
  "origin": "::1, 103.248.35.179",
  "url": "http://localhost/anything"
}
```

Note that both headers present and the header value of `X-Api-Version` configured in the Plugin overwrites the header value passed in the request.

### Rewrite URI And Append Headers

The following example demonstrates how you can rewrite the request Upstream URI and append additional header values. If the same headers present in the client request, their headers values will append to the configured header values in the plugin.

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "proxy-rewrite-route",
    "methods": ["GET"],
    "uri": "/",
    "plugins": {
      "proxy-rewrite": {
        "uri": "/headers",
        "headers": {
          "add": {
            "X-Api-Version": "v1",
            "X-Api-Engine": "apisix"
          }
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

Send a request to verify:

```shell
curl "http://127.0.0.1:9080/" -H '"X-Api-Version": "v2"'
```

You should see a response similar to the following:

```text
{
  "headers": {
    "Accept": "*/*",
    "Host": "httpbin.org",
    "User-Agent": "curl/8.2.1",
    "X-Amzn-Trace-Id": "Root=1-64fed73a-59cd3bd640d76ab16c97f1f1",
    "X-Api-Engine": "apisix",
    "X-Api-Version": "v1,v2",
    "X-Forwarded-Host": "127.0.0.1"
  }
}
```

Note that both headers present and the header value of `X-Api-Version` configured in the Plugin is appended by the header value passed in the request.

### Remove Existing Header

The following example demonstrates how you can remove an existing header `User-Agent`.

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "proxy-rewrite-route",
    "methods": ["GET"],
    "uri": "/headers",
    "plugins": {
      "proxy-rewrite": {
        "headers": {
          "remove":[
            "User-Agent"
          ]
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

Send a request to verify if the specified header is removed:

```shell
curl "http://127.0.0.1:9080/headers"
```

You should see a response similar to the following, where the `User-Agent` header is not present:

```text
{
  "headers": {
    "Accept": "*/*",
    "Host": "httpbin.org",
    "X-Amzn-Trace-Id": "Root=1-64fef302-07f2b13e0eb006ba776ad91d",
    "X-Forwarded-Host": "127.0.0.1"
  }
}
```

### Rewrite URI Using RegEx

The following example demonstrates how you can parse text from the original Upstream URI path and use them to compose a new Upstream URI path. In this example, APISIX is configured to forward all requests from `/test/user/agent` to `/user-agent`.

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "proxy-rewrite-route",
    "uri": "/test/*",
    "plugins": {
      "proxy-rewrite": {
        "regex_uri": ["^/test/(.*)/(.*)", "/$1-$2"]
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

Send a request to `/test/user/agent` to check if it is redirected to `/user-agent`:

```shell
curl "http://127.0.0.1:9080/test/user/agent"
```

You should see a response similar to the following:

```text
{
  "user-agent": "curl/8.2.1"
}
```

### Add URL Parameters

The following example demonstrates how you can add URL parameters to the request.

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "proxy-rewrite-route",
    "methods": ["GET"],
    "uri": "/get",
    "plugins": {
      "proxy-rewrite": {
        "uri": "/get?arg1=apisix&arg2=plugin"
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

Send a request to verify if the URL parameters are also forwarded to upstream:

```shell
curl "http://127.0.0.1:9080/get"
```

You should see a response similar to the following:

```text
{
  "args": {
    "arg1": "apisix",
    "arg2": "plugin"
  },
  "headers": {
    "Accept": "*/*",
    "Host": "127.0.0.1",
    "User-Agent": "curl/8.2.1",
    "X-Amzn-Trace-Id": "Root=1-64fef6dc-2b0e09591db7353a275cdae4",
    "X-Forwarded-Host": "127.0.0.1"
  },
  "origin": "127.0.0.1, 103.248.35.148",
  "url": "http://127.0.0.1/get?arg1=apisix&arg2=plugin"
}
```

### Rewrite HTTP Method

The following example demonstrates how you can rewrite a GET request into a POST request.

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "proxy-rewrite-route",
    "methods": ["GET"],
    "uri": "/get",
    "plugins": {
      "proxy-rewrite": {
        "uri": "/anything",
        "method":"POST"
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

Send a GET request to `/get` to verify if it is transformed into a POST request to `/anything`:

```shell
curl "http://127.0.0.1:9080/get"
```

You should see a response similar to the following:

```text
{
  "args": {},
  "data": "",
  "files": {},
  "form": {},
  "headers": {
    "Accept": "*/*",
    "Host": "127.0.0.1",
    "User-Agent": "curl/8.2.1",
    "X-Amzn-Trace-Id": "Root=1-64fef7de-0c63387645353998196317f2",
    "X-Forwarded-Host": "127.0.0.1"
  },
  "json": null,
  "method": "POST",
  "origin": "::1, 103.248.35.179",
  "url": "http://localhost/anything"
}
```

### Forward Consumer Names to Upstream

The following example demonstrates how you can forward the name of consumers who authenticates successfully to Upstream services. As an example, you will be using `key-auth` as the authentication method.

Create a Consumer `JohnDoe`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "JohnDoe"
  }'
```

Create `key-auth` credential for the Consumer:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/JohnDoe/credentials" -X PUT \
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

Next, create a Route with key authentication enabled, configure `proxy-rewrite` to add Consumer name to the header, and remove the authentication key so that it is not visible to the Upstream service:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "consumer-restricted-route",
    "uri": "/get",
    "plugins": {
      "key-auth": {},
      "proxy-rewrite": {
        "headers": {
          "set": {
            "X-Apisix-Consumer": "$consumer_name"
          },
          "remove": [ "Apikey" ]
        }
      }
    },
    "upstream" : {
      "nodes": {
        "httpbin.org":1
      }
    }
  }'
```

Send a request to the Route as Consumer `JohnDoe`:

```shell
curl -i "http://127.0.0.1:9080/get" -H 'apikey: john-key'
```

You should receive an `HTTP/1.1 200 OK` response with the following body:

```text
{
  "args": {},
  "headers": {
    "Accept": "*/*",
    "Host": "127.0.0.1",
    "User-Agent": "curl/8.4.0",
    "X-Amzn-Trace-Id": "Root=1-664b01a6-2163c0156ed4bff51d87d877",
    "X-Apisix-Consumer": "JohnDoe",
    "X-Forwarded-Host": "127.0.0.1"
  },
  "origin": "172.19.0.1, 203.12.12.12",
  "url": "http://127.0.0.1/get"
}
```

Send another request to the Route without the valid credential:

```shell
curl -i "http://127.0.0.1:9080/get"
```

You should receive an `HTTP/1.1 403 Forbidden` response.
