---
title: body-transformer
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - BODY TRANSFORMER
  - body-transformer
description: This document contains information about the Apache APISIX body-transformer Plugin.
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

This plugin is used to transform the request and/or response body from one
format to another format, e.g. JSON to XML.

Use cases:

- simple SOAP proxy
- generic template-based transform, e.g. JSON to JSON, JSON to HTML, XML to YAML

## Attributes

| Name      | Type | Required | Description |
| ----------- | ----------- |----------| ----------- |
| `request`      | object       | False    | request body transformation configuration      |
| `request.input_format`      | string       | False    | request body original format, if not specified, it would be determined from `Content-Type` header.      |
| `request.template`      | string       | True     | request body transformation template       |
| `request.template_is_base64`      | boolean       | False    | Set to true if the template is base64 encoded       |
| `response`      | object       | False    | response body transformation configuration      |
| `response.input_format`      | string       | False    | response body original format, if not specified, it would be determined from `Content-Type` header.       |
| `response.template`      | string       | True     | response body transformation template       |
| `response.template_is_base64`      | boolean       | False     | Set to true if the template is base64 encoded       |

## Enable Plugin

You can enable the Plugin on a specific Route as shown below:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/test_ws \
    -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["POST"],
    "uri": "/ws",
    "plugins": {
        "body-transformer": {
            "request": {
                "template": "..."
            },
            "response": {
                "template": "..."
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

## Configuration description

The `request` and `response` correspond to configurations of request body and response body transformation perspectively.

Specify one of them, or both of them, to fit your need.

`request`/`response`:

* `input_format` specifies the body original format:
  * `xml` (`text/xml`)
  * `json` (`application/json`)
* `template` specifies the [template](https://github.com/bungle/lua-resty-template) text used by transformation.

**Notes:**

`{{ ... }}` in lua-resty-template will do html-escape, e.g. space character, so if it's not what you wish, use `{* ... *}` instead.

If you do not specify `input_format` and no `Content-Type` header, or body is `nil`, then this plugin will not parse the body before template rendering.
In any case, you could access body string via `{{ _body }}`.

This is useful for below use cases:

* you wish to generate body from scratch based on Nginx/APISIX variables, even if the original body is `nil`.
* you wish to parse the body string yourself in the template via other lua modules, e.g. parse protobuf.

For example, parse YAML to JSON yourself:

```
{%
    local yaml = require("tinyyaml")
    local body = yaml.parse(_body)
%}
{"foobar":"{{body.foobar.foo .. " " .. body.foobar.bar}}"}
```

You must ensure `template` is a valid JSON string, i.e. you need to take care of special characters escape, e.g. double quote.
If it's cumbersome to escape big text file or complex file, you could use encode your template text file in base64 format instead.

For example, you could use `base64` command to encode your template text file:

```bash
curl http://127.0.0.1:9180/apisix/admin/routes/test_ws \
    -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["POST"],
    "uri": "/ws",
    "plugins": {
        "body-transformer": {
            "request": {
                "template": "'"$(base64 -w0 /path/to/my_template_file)"'"
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

In `template`, you can use below auxiliary functions to escape string to fit specific format:

* `_escape_json()`
* `_escape_xml()`

Note that `_escape_json()` would double quote the value of string type, so don't repeat double-quote in the template, e.g. `{"foobar":{*_escape_json(name)*}}`.

And, you can refer to `_ctx` to access nginx request context, e.g. `{{ _ctx.var.status }}`.

## Example

Let's take a simple SOAP proxy as example.

* from downstream to upstream, it transforms the request body from JSON to XML
* from upstream to downstream, it transforms the response body from XML to JSON
  * the response `template` distinguishes the normal response from the fault response

### Run a test web service server

```bash
cd /tmp
git clone https://github.com/spring-guides/gs-soap-service.git
cd gs-soap-service
./mvnw spring-boot:run
```

### Test

```bash
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

curl http://127.0.0.1:9180/apisix/admin/routes/test_ws \
    -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["POST"],
    "uri": "/ws",
    "plugins": {
        "proxy-rewrite": {
            "headers": {
                "set": {
                    "Accept-Encoding": "identity",
                    "Content-Type": "text/xml"
                }
            }
        },
        "response-rewrite": {
            "headers": {
                "set": {
                    "Content-Type": "application/json"
                }
            }
        },
        "body-transformer": {
            "request": {
                "template": "'"$req_template"'"
            },
            "response": {
                "template": "'"$rsp_template"'"
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

curl -s http://127.0.0.1:9080/ws -H 'content-type: application/json' -X POST -d '{"name": "Spain"}' | jq
{
  "status": "200",
  "currency": "EUR",
  "population": 46704314,
  "capital": "Madrid",
  "name": "Spain"
}

# Fault response
curl -s http://127.0.0.1:9080/ws -H 'content-type: application/json' -X POST -d '{"name": "Spain"}' | jq
{
  "message": "Your name is required.",
  "code": "SOAP-ENV:Server"
}
```

## Delete Plugin

To remove the `body-transformer` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/test_ws \
    -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["POST"],
    "uri": "/ws",
    "plugins": {},
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "localhost:8080": 1
        }
    }
}'
```
