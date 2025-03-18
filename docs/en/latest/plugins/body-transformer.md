---
title: body-transformer
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - BODY TRANSFORMER
  - body-transformer
description: The body-transformer Plugin performs template-based transformations to transform the request and/or response bodies from one format to another, for example, from JSON to JSON, JSON to HTML, or XML to YAML.
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

## Description

The `body-transformer` Plugin performs template-based transformations to transform the request and/or response bodies from one format to another, for example, from JSON to JSON, JSON to HTML, or XML to YAML.

## Attributes

| Name          | Type    | Required | Default | Valid values | Description                                |
| ------------- | ------- | -------- | ------- | ------------ | ------------------------------------------ |
| `request`      | object       | False      | | | Request body transformation configuration.      |
| `request.input_format`      | string       | False      | | [`xml`,`json`,`encoded`,`args`,`plain`,`multipart`] | Request body original media type. If unspecified, the value would be determined by the `Content-Type` header to apply the corresponding decoder. The `xml` option corresponds to `text/xml` media type. The `json` option corresponds to `application/json` media type. The `encoded` option corresponds to `application/x-www-form-urlencoded` media type. The `args` option corresponds to GET requests. The `plain` option corresponds to `text/plain` media type. The `multipart` option corresponds to `multipart/related` media type. If the media type is neither type, the value would be left unset and the transformation template will be directly applied.      |
| `request.template`      | string       | True      | | | Request body transformation template. The template uses [lua-resty-template](https://github.com/bungle/lua-resty-template) syntax. See the [template syntax](https://github.com/bungle/lua-resty-template#template-syntax) for more details. You can also use auxiliary functions `_escape_json()` and `_escape_xml()` to escape special characters such as double quotes, `_body` to access request body, and `_ctx` to access context variables.    |
| `request.template_is_base64`      | boolean       | False    | false | | Set to true if the template is base64 encoded.      |
| `response`      | object       | False      | | | Response body transformation configuration.     |
| `response.input_format`      | string       | False      | | [`xml`,`json`] | Response body original media type. If unspecified, the value would be determined by the `Content-Type` header to apply the corresponding decoder. If the media type is neither `xml` nor `json`, the value would be left unset and the transformation template will be directly applied.       |
| `response.template`      | string       | True      | | | Response body transformation template.       |
| `response.template_is_base64`      | boolean       | False     | false | | Set to true if the template is base64 encoded.       |

## Examples

The examples below demonstrate how you can configure `body-transformer` for different scenarios.

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

The transformation template uses [lua-resty-template](https://github.com/bungle/lua-resty-template) syntax. See the [template syntax](https://github.com/bungle/lua-resty-template#template-syntax) to learn more.

You can also use auxiliary functions `_escape_json()` and `_escape_xml()` to escape special characters such as double quotes, `_body` to access request body, and `_ctx` to access context variables.

In all cases, you should ensure that the transformation template is a valid JSON string.

### Transform between JSON and XML SOAP

The following example demonstrates how to transform the request body from JSON to XML and the response body from XML to JSON when working with a SOAP Upstream service.

Start the sample SOAP service:

```shell
cd /tmp
git clone https://github.com/spring-guides/gs-soap-service.git
cd gs-soap-service/complete
./mvnw spring-boot:run
```

Create the request and response transformation templates:

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

`awk` and `tr` are used above to manipulate the template such that the template would be a valid JSON string.

Create a Route with `body-transformer` using the templates created previously. In the Plugin, set the request input format as JSON, the response input format as XML, and the `Content-Type` header to `text/xml` for the Upstream service to respond properly:

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

If it is cumbersome to adjust complex text files to be valid transformation templates, you can use the base64 utility to encode the files, such as the following:

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

Send a request with a valid JSON body:

```shell
curl "http://127.0.0.1:9080/ws" -X POST -d '{"name": "Spain"}'
```

The JSON body sent in the request will be transformed into XML before being forwarded to the Upstream SOAP service, and the response body will be transformed back from XML to JSON.

You should see a response similar to the following:

```json
{
  "status": "200",
  "currency": "EUR",
  "population": 46704314,
  "capital": "Madrid",
  "name": "Spain"
}
```

### Modify Request Body

The following example demonstrates how to dynamically modify the request body.

Create a Route with `body-transformer`, in which the template appends the word `world` to the `name` and adds `10` to the `age` to set them as values to `foo` and `bar` respectively:

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

Send a request to the Route:

```shell
curl "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -d '{"name":"hello","age":20}' \
  -i
```

You should see a response of the following:

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

### Generate Request Body Using Variables

The following example demonstrates how to generate request body dynamically using the `ctx` context variables.

Create a Route with `body-transformer`, in which the template accesses the request argument using the [Nginx variable](https://nginx.org/en/docs/http/ngx_http_core_module.html) `arg_name`:

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

Send a request to the Route with `name` argument:

```shell
curl -i "http://127.0.0.1:9080/anything?name=hello"
```

You should see a response like this:

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

### Transform Body from YAML to JSON

The following example demonstrates how to transform request body from YAML to JSON.

Create the request transformation template:

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

Create a Route with `body-transformer` that uses the template:

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

Send a request to the Route with a YAML body:

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

You should see a response similar to the following, which verifies that the YAML body was appropriately transformed to JSON:

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

### Transform Form URL Encoded Body to JSON

The following example demonstrates how to transform `form-urlencoded` body to JSON.

Create a Route with `body-transformer` which sets the `input_format` to `encoded` and configures a template that appends string `world` to the `name` input, add `10` to the `age` input:

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

Send a POST request to the Route with an encoded body:

```shell
curl "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d 'name=hello&age=20'
```

You should see a response similar to the following:

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

### Transform GET Request Query Parameter to Body

The following example demonstrates how to transform a GET request query parameter to request body. Note that this does not transform the HTTP method. To transform the method, see [`proxy-rewrite`](./proxy-rewrite.md).

Create a Route with `body-transformer`, which sets the `input_format` to `args` and configures a template that adds a message to the request:

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

Send a GET request to the Route:

```shell
curl "http://127.0.0.1:9080/anything?name=john"
```

You should see a response similar to the following:

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

### Transform Plain Media Type

The following example demonstrates how to transform requests with `plain` media type.

Create a Route with `body-transformer`, which sets the `input_format` to `plain` and configures a template to remove `not` and a subsequent space from the body string:

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

Send a POST request to the Route:

```shell
curl "http://127.0.0.1:9080/anything" -X POST \
  -d 'not actually json' \
  -i
```

You should see a response similar to the following:

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

### Transform Multipart Media Type

The following example demonstrates how to transform requests with `multipart` media type.

Create a request transformation template which adds a `status` to the body based on the `age` provided in the request body:

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

Create a Route with `body-transformer`, which sets the `input_format` to `multipart` and uses the previously created request template for transformation:

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

Send a multipart POST request to the Route:

```shell
curl -X POST \
  -F "name=john" \
  -F "age=10" \
  "http://127.0.0.1:9080/anything"
```

You should see a response similar to the following:

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
