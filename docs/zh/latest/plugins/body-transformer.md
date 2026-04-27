---
title: body-transformer
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - BODY TRANSFORMER
  - body-transformer
description: body-transformer 插件执行基于模板的转换，将请求和/或响应主体从一种格式转换为另一种格式，例如从 JSON 到 JSON、从 JSON 到 HTML 或从 XML 到 YAML。
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
  <link rel="canonical" href="https://docs.api7.ai/hub/body-transformer" />
</head>

## 描述

`body-transformer` 插件执行基于模板的转换，将请求和/或响应主体从一种格式转换为另一种格式，例如从 JSON 到 JSON、从 JSON 到 HTML 或从 XML 到 YAML。

## 属性

| 名称           | 类型                   | 必选项   | 默认值           | 有效值 | 描述                                                                                                                                         |
|--------------|----------------------|-------|---------------|--------------|--------------------------------------------------------------------------------------------------------------------------------------------|
| `request` | object | 否 | | | 请求体转换配置。 |
| `request.input_format` | string | 否 | | [`xml`,`json`,`encoded`,`args`,`plain`,`multipart`] | 请求体原始媒体类型。若未指定，则该值将由 `Content-Type` 标头确定以应用相应的解码器。`xml` 选项对应于 `text/xml` 媒体类型。`json` 选项对应于 `application/json` 媒体类型。`encoded` 选项对应于 `application/x-www-form-urlencoded` 媒体类型。`args` 选项对应于 GET 请求。`plain` 选项对应于 `text/plain` 媒体类型。`multipart` 选项对应于 `multipart/related` 媒体类型。如果媒体类型不是这两种类型，则该值将保留未设置状态并直接应用转换模板。 |
| `request.template` | string | True | | | 请求体转换模板。模板使用 [lua-resty-template](https://github.com/bungle/lua-resty-template) 语法。有关更多详细信息，请参阅 [模板语法](https://github.com/bungle/lua-resty-template#template-syntax)。您还可以使用辅助函数 `_escape_json()` 和 `_escape_xml()` 转义双引号等特殊字符，使用 `_body` 访问请求正文，使用 `_ctx` 访问上下文变量。|
| `request.template_is_base64` | boolean | 否 | false | | 如果模板是 base64 编码的，则设置为 true。|
| `response` | object | 否 | | | 响应体转换配置。|
| `response.input_format` | string | 否 | | [`xml`,`json`,`encoded`,`args`,`plain`,`multipart`] | 响应体原始媒体类型。若未指定，则在可识别的情况下会根据 `Content-Type` 标头自动确定解码器：`xml` 对应 `text/xml`，`json` 对应 `application/json`，`encoded` 对应 `application/x-www-form-urlencoded`，`multipart` 对应任意 `multipart/*` 内容类型。`args` 选项表示读取请求的 URI query args，而非解码响应体。`plain` 选项需显式指定，不会从 `Content-Type: text/plain` 自动识别。如果媒体类型不属于上述任一受支持的类型，则该值将保留未设置状态并直接应用转换模板。|
| `response.template` | string | True | | | 响应主体转换模板。|
| `response.template_is_base64` | boolean | 否 | false | | 如果模板是 base64 编码的，则设置为 true。|

## 示例

以下示例演示了如何针对不同场景配置 `body-transformer`。

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

转换模板使用 [lua-resty-template](https://github.com/bungle/lua-resty-template) 语法。请参阅 [模板语法](https://github.com/bungle/lua-resty-template#template-syntax) 了解更多信息。

您还可以使用辅助函数 `_escape_json()` 和 `_escape_xml()` 转义特殊字符（例如双引号）、`_body` 访问请求正文以及 `_ctx` 访问上下文变量。

在所有情况下，您都应确保转换模板是有效的 JSON 字符串。

### JSON 和 XML SOAP 之间的转换

以下示例演示了在使用 SOAP 上游服务时如何将请求主体从 JSON 转换为 XML，将响应主体从 XML 转换为 JSON。

启动示例 SOAP 服务：

```shell
cd /tmp
git clone https://github.com/spring-guides/gs-soap-service.git
cd gs-soap-service/complete
./mvnw spring-boot:run
```

创建请求和响应转换模板：

```shell
req_template=$(cat <<EOF | awk '{gsub(/"/,"\\\"");};1' | awk '{$1=$1};1' | tr -d '\r\n'
<?xml version="1.0"?>
<soap-env:Envelope xmlns:soap-env="http://schemas.xmlsoap.org/soap/envelope/">
 <soap-env:Body>
  <ns0:getCountryRequest xmlns:ns0="http://spring.io/guides/gs-producing-web-service">
   <ns0:name>{{_escape_xml(name)}}</ns0:name>
  </ns0:getCountryRequest>
 </soap-env:Body>
</soap-env:Envelope>
EOF
)

rsp_template=$(cat <<EOF | awk '{gsub(/"/,"\\\"");};1' | awk '{$1=$1};1' | tr -d '\r\n'
{% if Envelope.Body.Fault == nil then %}
{
  "status":"{{_ctx.var.status}}",
  "currency":"{{Envelope.Body.getCountryResponse.country.currency}}",
  "population":{{Envelope.Body.getCountryResponse.country.population}},
  "capital":"{{Envelope.Body.getCountryResponse.country.capital}}",
  "name":"{{Envelope.Body.getCountryResponse.country.name}}"
}
{% else %}
{
  "message":{*_escape_json(Envelope.Body.Fault.faultstring[1])*},
  "code":"{{Envelope.Body.Fault.faultcode}}"
  {% if Envelope.Body.Fault.faultactor ~= nil then %}
  , "actor":"{{Envelope.Body.Fault.faultactor}}"
  {% end %}
}
{% end %}
EOF
)
```

上面使用了 `awk` 和 `tr` 来操作模板，使模板成为有效的 JSON 字符串。

使用之前创建的模板创建带有 `body-transformer` 的路由。在插件中，将请求输入格式设置为 JSON，将响应输入格式设置为 XML，并将 `Content-Type` 标头设置为 `text/xml`，以便上游服务正确响应：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "body-transformer-route",
    "methods": ["POST"],
    "uri": "/ws",
    "plugins": {
      "body-transformer": {
        "request": {
          "template": "'"$req_template"'",
          "input_format": "json"
        },
        "response": {
          "template": "'"$rsp_template"'",
          "input_format": "xml"
        }
      },
      "proxy-rewrite": {
        "headers": {
          "set": {
            "Content-Type": "text/xml"
          }
        }
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "localhost:8080": 1
      }
    }
  }'
```

:::tip

如果将复杂的文本文件调整为有效的转换模板很麻烦，则可以使用 base64 实用程序对文件进行编码，例如以下内容：

```json
"body-transformer": {
  "request": {
    "template": "'"$(base64 -w0 /path/to/request_template_file)"'"
  },
  "response": {
    "template": "'"$(base64 -w0 /path/to/response_template_file)"'"
  }
}
```

:::

发送具有有效 JSON 主体的请求：

```shell
curl "http://127.0.0.1:9080/ws" -X POST -d '{"name": "Spain"}'
```

请求中发送的 JSON 主体将在转发到上游 SOAP 服务之前转换为 XML，响应主体将从 XML 转换回 JSON。

您应该会看到类似以下内容的响应：

```json
{
  "status": "200",
  "currency": "EUR",
  "population": 46704314,
  "capital": "Madrid",
  "name": "Spain"
}
```

### 修改请求体

以下示例演示了如何动态修改请求体。

使用 `body-transformer` 创建一个路由，其中​​模板将单词 `world` 附加到 `name`，并将 `10` 添加到 `age`，以将它们分别设置为 `foo` 和 `bar` 的值：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "body-transformer-route",
    "uri": "/anything",
    "plugins": {
      "body-transformer": {
        "request": {
          "template": "{\"foo\":\"{{name .. \" world\"}}\",\"bar\":{{age+10}}}"
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

向路线发送请求：

```shell
curl "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -d '{"name":"hello","age":20}' \
  -i
```

您应该看到以下响应：

```json
{
  "args": {},
  "data": "{\"foo\":\"hello world\",\"bar\":30}",
  ...
  "json": {
    "bar": 30,
    "foo": "hello world"
  },
  "method": "POST",
  ...
}
```

### 使用变量生成请求主体

以下示例演示如何使用 `ctx` 上下文变量动态生成请求主体。

使用 `body-transformer` 创建路由，其中​​模板使用 [Nginx 变量](https://nginx.org/en/docs/http/ngx_http_core_module.html) `arg_name` 访问请求参数：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "body-transformer-route",
    "uri": "/anything",
    "plugins": {
      "body-transformer": {
        "request": {
          "template": "{\"foo\":\"{{_ctx.var.arg_name .. \" world\"}}\"}"
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

使用 `name` 参数向路由发送请求：

```shell
curl -i "http://127.0.0.1:9080/anything?name=hello"
```

您应该看到如下响应：

```json
{
  "args": {
    "name": "hello"
  },
  ...,
  "json": {
    "foo": "hello world"
  },
...
}
```

### 将正文从 YAML 转换为 JSON

以下示例演示如何将请求正文从 YAML 转换为 JSON。

创建请求转换模板：

```shell
req_template=$(cat <<EOF | awk '{gsub(/"/,"\\\"");};1'
{%
    local yaml = require("tinyyaml")
    local body = yaml.parse(_body)
%}
{"foobar":"{{body.foobar.foo .. " " .. body.foobar.bar}}"}
EOF
)
```

使用以下模板创建一个带有 `body-transformer` 的路由：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "body-transformer-route",
    "uri": "/anything",
    "plugins": {
      "body-transformer": {
        "request": {
          "template": "'"$req_template"'"
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

使用 YAML 主体向路由发送请求：

```shell
body='
foobar:
  foo: hello
  bar: world'

curl "http://127.0.0.1:9080/anything" -X POST \
  -d "$body" \
  -H "Content-Type: text/yaml" \
  -i
```

您应该会看到类似以下内容的响应，这验证了 YAML 主体已适当地转换为 JSON：

```json
{
  "args": {},
  "data": "{\"foobar\":\"hello world\"}",
  ...
  "json": {
    "foobar": "hello world"
  },
...
}
```

### 将表单 URL 编码主体转换为 JSON

以下示例演示如何将 `form-urlencoded` 主体转换为 JSON。

使用 `body-transformer` 创建路由，将 `input_format` 设置为 `encoded`，并配置一个模板，将字符串 `world` 附加到 `name` 输入，将 `10` 添加到 `age` 输入：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "body-transformer-route",
    "uri": "/anything",
    "plugins": {
      "body-transformer": {
        "request": {
          "input_format": "encoded",
          "template": "{\"foo\":\"{{name .. \" world\"}}\",\"bar\":{{age+10}}}"
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

向路由发送一个带有编码主体的 POST 请求：

```shell
curl "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d 'name=hello&age=20'
```

您应该会看到类似以下内容的响应：

```json
{
  "args": {},
  "data": "",
  "files": {},
  "form": {
    "{\"foo\":\"hello world\",\"bar\":30}": ""
  },
  "headers": {
    ...
  },
  ...
}
```

### 将 GET 请求查询参数转换为正文

以下示例演示如何将 GET 请求查询参数转换为请求正文。请注意，这不会转换 HTTP 方法。要转换方法，请参阅 [`proxy-rewrite`](./proxy-rewrite.md)。

使用 `body-transformer` 创建路由，将 `input_format` 设置为 `args`，并配置一个向请求添加消息的模板：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "body-transformer-route",
    "uri": "/anything",
    "plugins": {
      "body-transformer": {
        "request": {
          "input_format": "args",
          "template": "{\"message\": \"hello {{name}}\"}"
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

向路线发送 GET 请求：

```shell
curl "http://127.0.0.1:9080/anything?name=john"
```

您应该会看到类似以下内容的响应：

```json
{
  "args": {},
  "data": "{\"message\": \"hello john\"}",
  "files": {},
  "form": {},
  "headers": {
    ...
  },
  "json": {
    "message": "hello john"
  },
  "method": "GET",
  ...
}
```

### 转换纯文本媒体类型

以下示例演示如何转换具有 `plain` 媒体类型的请求。

使用 `body-transformer` 创建路由，将 `input_format` 设置为 `plain`，并配置模板以从正文字符串中删除 `not` 和后续空格：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "body-transformer-route",
    "uri": "/anything",
    "plugins": {
      "body-transformer": {
        "request": {
          "input_format": "plain",
          "template": "{\"message\": \"{* string.gsub(_body, \"not \", \"\") *}\"}"
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

向路由发送 POST 请求：

```shell
curl "http://127.0.0.1:9080/anything" -X POST \
  -d 'not actually json' \
  -i
```

您应该会看到类似以下内容的响应：

```json
{
  "args": {},
  "data": "",
  "files": {},
  "form": {
    "{\"message\": \"actually json\"}": ""
  },
  "headers": {
    ...
  },
  ...
}
```

### 转换多部分媒体类型

以下示例演示如何转换具有 `multipart` 媒体类型的请求。

创建一个请求转换模板，该模板根据请求正文中提供的 `age` 向正文添加 `status`：

```shell
req_template=$(cat <<EOF | awk '{gsub(/"/,"\\\"");};1'
{%
  local core = require 'apisix.core'
  local cjson = require 'cjson'

  if tonumber(context.age) > 18 then
      context._multipart:set_simple("status", "adult")
  else
      context._multipart:set_simple("status", "minor")
  end

  local body = context._multipart:tostring()
%}{* body *}
EOF
)
```

创建一个带有 `body-transformer` 的路由，将 `input_format` 设置为 `multipart`，并使用之前创建的请求模板进行转换：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "body-transformer-route",
    "uri": "/anything",
    "plugins": {
      "body-transformer": {
        "request": {
          "input_format": "multipart",
          "template": "'"$req_template"'"
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

向路由发送多部分 POST 请求：

```shell
curl -X POST \
  -F "name=john" \
  -F "age=10" \
  "http://127.0.0.1:9080/anything"
```

您应该会看到类似以下内容的响应：

```json
{
  "args": {},
  "data": "",
  "files": {},
  "form": {
    "age": "10",
    "name": "john",
    "status": "minor"
  },
  "headers": {
    "Accept": "*/*",
    "Content-Length": "361",
    "Content-Type": "multipart/form-data; boundary=------------------------qtPjk4c8ZjmGOXNKzhqnOP",
    ...
  },
  ...
}
```

### 根据消费者身份转换响应体

以下示例演示如何根据不同消费者身份自定义响应体转换。该示例展示如何向不同消费者返回不同的响应格式，同时过滤敏感字段和重命名属性。

创建根据消费者身份应用不同转换的响应转换模板：

```shell
rsp_template=$(cat <<EOF | awk '{gsub(/"/,"\\\"");};1' | awk '{$1=$1};1' | tr -d '\r\n'
{% local consumer_name = _ctx.consumer and _ctx.consumer.username or "" %}
{% if consumer_name == "consumer-a" then %}
{
  "user_id": {* user_id *},
  "display_name": {* _escape_json(username) *},
  "email": {* _escape_json(email) *}
}
{% elseif consumer_name == "consumer-b" then %}
{
  "user_id": {* user_id *},
  "email": {* _escape_json(email) *},
  "balance": {* balance *}
}
{% else %}
{* _body *}
{% end %}
EOF
)
```

创建三个配置了 `key-auth` 的消费者：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "consumer-a",
    "plugins": {
      "key-auth": {
        "key": "consumer-a"
      }
    }
  }'

curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "consumer-b",
    "plugins": {
      "key-auth": {
        "key": "consumer-b"
      }
    }
  }'

curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "consumer-c",
    "plugins": {
      "key-auth": {
        "key": "consumer-c"
      }
    }
  }'
```

创建一个配置了 `body-transformer`、`key-auth` 和 `mocking` 插件的路由：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "body-transformer-route",
    "uri": "/mock",
    "plugins": {
      "key-auth": {},
      "mocking": {
        "response_example": "{\"user_id\":1001,\"username\":\"john_doe\",\"email\":\"john@example.com\",\"phone\":\"+1-555-0123\",\"balance\":1250.50}"
      },
      "body-transformer": {
        "response": {
          "input_format": "json",
          "template": "'"$rsp_template"'"
        }
      }
    }
  }'
```

使用不同的 `apikey` 请求头发送请求以验证响应转换。

以 `consumer-a` 身份发送请求：

```shell
curl "http://127.0.0.1:9080/mock" -H "apikey: consumer-a"
```

您应该会看到类似以下内容的响应，其中演示了以下转换：

- `username` 字段已重命名为 `display_name`
- 敏感的 `phone` 和 `balance` 字段已被过滤

```json
{
  "user_id": 1001,
  "display_name": "john_doe",
  "email": "john@example.com"
}
```

以 `consumer-b` 身份发送请求：

```shell
curl "http://127.0.0.1:9080/mock" -H "apikey: consumer-b"
```

您应该会看到类似以下内容的响应，其中演示了以下转换：

- `username` 和 `phone` 字段已被过滤
- `balance` 字段已被保留

```json
{
  "user_id": 1001,
  "email": "john@example.com",
  "balance": 1250.50
}
```

以 `consumer-c` 身份发送请求：

```shell
curl "http://127.0.0.1:9080/mock" -H "apikey: consumer-c"
```

您应该会看到类似以下内容的响应，显示原始响应未经更改地返回：

```json
{
  "user_id": 1001,
  "username": "john_doe",
  "email": "john@example.com",
  "phone": "+1-555-0123",
  "balance": 1250.50
}
```

### 根据消费者身份转换嵌套响应体

以下示例演示如何根据不同消费者身份自定义响应体转换。该示例展示如何提取嵌套字段、重新组织数据结构，并在向不同消费者提供不同响应格式的同时扁平化嵌套对象。

创建根据消费者身份提取和重新组织嵌套 JSON 字段的响应转换模板：

```shell
rsp_template=$(cat <<EOF | awk '{gsub(/"/,"\\\"");};1' | awk '{$1=$1};1' | tr -d '\r\n'
{% local consumer_name = _ctx.consumer and _ctx.consumer.username or "" %}
{% if consumer_name == "consumer-a" then %}
{
  "user_id": {* id *},
  "user_name": {* _escape_json(name) *},
  "email": {* _escape_json(profile.email) *},
  "location": {
    "city": {* _escape_json(profile.address.city) *},
    "country": {* _escape_json(profile.address.country) *}
  },
  "created_at": {* _escape_json(metadata.created_at) *}
}
{% elseif consumer_name == "consumer-b" then %}
{
  "id": {* id *},
  "name": {* _escape_json(name) *},
  "status": {* _escape_json(status) *},
  "profile": {
    "email": {* _escape_json(profile.email) *},
    "address": {
      "city": {* _escape_json(profile.address.city) *}
    }
  }
}
{% else %}
{* _body *}
{% end %}
EOF
)
```

创建配置了 `key-auth` 的消费者：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "consumer-a",
    "plugins": {
      "key-auth": {
        "key": "consumer-a"
      }
    }
  }'

curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "consumer-b",
    "plugins": {
      "key-auth": {
        "key": "consumer-b"
      }
    }
  }'

curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "consumer-c",
    "plugins": {
      "key-auth": {
        "key": "consumer-c"
      }
    }
  }'
```

使用嵌套结构模板创建配置了 `body-transformer`、`key-auth` 和 `mocking` 插件的路由：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "body-transformer-route",
    "uri": "/mock",
    "plugins": {
      "key-auth": {},
      "mocking": {
        "response_example": "{\"id\":123,\"name\":\"John Doe\",\"status\":\"active\",\"profile\":{\"email\":\"john@example.com\",\"address\":{\"city\":\"New York\",\"country\":\"USA\"}},\"metadata\":{\"created_at\":\"2024-01-01\",\"tags\":[\"vip\",\"premium\"]}}"
      },
      "body-transformer": {
        "response": {
          "input_format": "json",
          "template": "'"$rsp_template"'"
        }
      }
    }
  }'
```

以 `consumer-a` 身份发送请求以验证嵌套结构转换：

```shell
curl "http://127.0.0.1:9080/mock" -H "apikey: consumer-a"
```

您应该会看到类似以下内容的响应，其中演示了以下嵌套字段转换：

- `profile.email` 已被提取到顶层 `email`
- `profile.address.city` 和 `profile.address.country` 已合并为新的 `location` 对象
- `metadata.created_at` 已被提取到顶层 `created_at`

```json
{
  "user_id": 123,
  "user_name": "John Doe",
  "email": "john@example.com",
  "location": {
    "city": "New York",
    "country": "USA"
  },
  "created_at": "2024-01-01"
}
```

以 `consumer-b` 身份发送请求以验证嵌套结构转换：

```shell
curl "http://127.0.0.1:9080/mock" -H "apikey: consumer-b"
```

您应该会看到类似以下内容的响应，其中演示了以下转换：

- 原始 `profile` 对象结构已被保留
- `profile.address.country` 和 `metadata` 字段已被过滤

```json
{
  "id": 123,
  "name": "John Doe",
  "status": "active",
  "profile": {
    "email": "john@example.com",
    "address": {
      "city": "New York"
    }
  }
}
```

以 `consumer-c` 身份发送请求以验证嵌套结构转换：

```shell
curl "http://127.0.0.1:9080/mock" -H "apikey: consumer-c"
```

您应该会看到类似以下内容的响应，显示原始嵌套响应未经更改地返回：

```json
{
  "id": 123,
  "name": "John Doe",
  "status": "active",
  "profile": {
    "email": "john@example.com",
    "address": {
      "city": "New York",
      "country": "USA"
    }
  },
  "metadata": {
    "created_at": "2024-01-01",
    "tags": ["vip", "premium"]
  }
}
```
