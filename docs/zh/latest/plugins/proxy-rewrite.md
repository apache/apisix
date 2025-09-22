---
title: proxy-rewrite
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - Proxy Rewrite
  - proxy-rewrite
description: proxy-rewrite 插件支持重写 APISIX 转发到上游服务的请求。使用此插件，您可以修改 HTTP 方法、请求目标上游地址、请求标头等。
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

## 描述

`proxy-rewrite` 插件支持重写 APISIX 转发到上游服务的请求。使用此插件，您可以修改 HTTP 方法、请求目标上游地址、请求标头等。

## 属性

| 名称 | 类型 | 必需 | 默认值 | 有效值 | 描述 |
|-----------------------------|-----------|----------|---------|------------------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| uri | string | 否 | | | 新的上游 URI 路径。值支持 [Nginx 变量](https://nginx.org/en/docs/http/ngx_http_core_module.html)。例如，`$arg_name`。 |
| method | string | 否 | | ["GET", "POST", "PUT", "HEAD", "DELETE", "OPTIONS","MKCOL", "COPY", "MOVE", "PROPFIND", "PROPFIND","LOCK", "UNLOCK", "PATCH", "TRACE"] | 要使用的重写请求的 HTTP 方法。 |
| regex_uri | array[string] | 否 | | | 用于匹配客户端请求的 URI 路径并组成新的上游 URI 路径的正则表达式。当同时配置 `uri` 和 `regex_uri` 时，`uri` 具有更高的优先级。该数组应包含一个或多个 **键值对**，其中键是用于匹配 URI 的正则表达式，值是新的上游 URI 路径。例如，对于 `["^/iresty/(. *)/(. *)", "/$1-$2", ^/theothers/*", "/theothers"]`，如果请求最初发送到 `/iresty/hello/world`，插件会将上游 URI 路径重写为 `/iresty/hello-world`；如果请求最初发送到 `/theothers/hello/world`，插件会将上游 URI 路径重写为 `/theothers`。|
| host | string | 否 | | | 设置 [`Host`](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Host) 请求标头。|
| headers | object | 否 | | | 要执行的标头操作。可以设置为动作动词 `add`、`remove` 和/或 `set` 的对象；或由要 `set` 的标头组成的对象。当配置了多个动作动词时，动作将按照“添加”、“删除”和“设置”的顺序执行。|
| headers.add | object | 否 | | | 要附加到请求的标头。如果请求中已经存在标头，则会附加标头值。标头值可以设置为常量、一个或多个 [Nginx 变量](https://nginx.org/en/docs/http/ngx_http_core_module.html)，或者 `regex_uri` 的匹配结果（使用变量，例如 `$1-$2-$3`）。|
| headers.set | object | 否 | | | 要设置请求的标头。如果请求中已经存在标头，则会覆盖标头值。标头值可以设置为常量、一个或多个 [Nginx 变量](https://nginx.org/en/docs/http/ngx_http_core_module.html)，或者 `regex_uri` 的匹配结果（使用变量，例如 `$1-$2-$3`）。不应将其用于设置 `Host`。|
| headers.remove | array[string] | 否 | | | 从请求中删除的标头。
| use_real_request_uri_unsafe | boolean | 否 | false | | 如果为 True，则绕过 URI 规范化并允许完整的原始请求 URI。启用此选项被视为不安全。|

## 示例

下面的示例说明如何在不同场景中在路由上配置 `proxy-rewrite`。

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### 重写主机标头

以下示例演示了如何修改请求中的 `Host` 标头。请注意，您不应使用 `headers.set` 来设置 `Host` 标头。

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

向 `/headers` 发送请求以检查发送到上游的所有请求标头：

```shell
curl "http://127.0.0.1:9080/headers"
```

您应该看到类似于以下内容的响应：

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

### 重写 URI 并设置标头

以下示例演示了如何重写请求上游 URI 并设置其他标头值。如果客户端请求中存在相同的标头，则插件中设置的相应标头值将覆盖客户端请求中存在的值。

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

发送请求以验证：

```shell
curl "http://127.0.0.1:9080/" -H '"X-Api-Version": "v2"'
```

您应该看到类似于以下内容的响应：

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

注意到其中两个标头都存在，以及插件中配置的 `X-Api-Version` 标头值覆盖了请求中传递的标头值。

### 重写 URI 并附加标头

以下示例演示了如何重写请求上游 URI 并附加其他标头值。如果客户端请求中存在相同的标头，则它们的标头值将附加到插件中配置的标头值。

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

发送请求以验证：

```shell
curl "http://127.0.0.1:9080/" -H '"X-Api-Version": "v2"'
```

您应该会看到类似以下内容的响应：

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

请注意，两个标头均存在，并且插件中配置的 `X-Api-Version` 标头值均附加在请求中传递的标头值上。

### 删除现有标头

以下示例演示了如何删除现有标头 `User-Agent`。

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

发送请求来验证指定的标头是否被删除：

```shell
curl "http://127.0.0.1:9080/headers"
```

您应该看到类似以下的响应，其中 `User-Agen` 标头已被移除：

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

### 使用 RegEx 重写 URI

以下示例演示了如何解析原始上游 URI 路径中的文本并使用它们组成新的上游 URI 路径。在此示例中，APISIX 配置为将所有请求从 `/test/user/agent` 转发到 `/user-agent`。

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

发送请求到 `/test/user/agent`，检查是否被重定向到 `/user-agent`：

```shell
curl "http://127.0.0.1:9080/test/user/agent"
```

您应该会看到类似以下内容的响应：

```text
{
  "user-agent": "curl/8.2.1"
}
```

### 添加 URL 参数

以下示例演示了如何向请求添加 URL 参数。

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

发送请求来验证 URL 参数是否也转发给了上游：

```shell
curl "http://127.0.0.1:9080/get"
```

您应该会看到类似以下内容的响应：

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

### 重写 HTTP 方法

以下示例演示如何将 GET 请求重写为 POST 请求。

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

向 `/get` 发送 GET 请求，以验证它是否转换为向 `/anything` 发送 POST 请求：

```shell
curl "http://127.0.0.1:9080/get"
```

您应该会看到类似以下内容的响应：

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

### 将消费者名称转发到上游

以下示例演示了如何将成功验证的消费者名称转发到上游服务。例如，您将使用 `key-auth` 作为身份验证方法。

创建消费者 `JohnDoe`：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "JohnDoe"
  }'
```

为消费者创建 `key-auth` 凭证：

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

接下来，创建一个启用密钥认证的路由，配置 `proxy-rewrite` 以将消费者名称添加到标头，并删除认证密钥，以使其对上游服务不可见：

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

以消费者 `JohnDoe` 的身份向路由发送请求：

```shell
curl -i "http://127.0.0.1:9080/get" -H 'apikey: john-key'
```

您应该收到一个包含以下主体的 `HTTP/1.1 200 OK` 响应：

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

向路由发送另一个请求，不带有有效凭证：

```shell
curl -i "http://127.0.0.1:9080/get"
```

您应该收到 `HTTP/1.1 403 Forbidden` 响应。
