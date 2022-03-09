---
title: recaptcha
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

## Name

Restrict access to an upstream service by verifying request captcha token to the Google reCAPTCHA service. The Plugin supports customizingthe invalid captcha response.

## Attributes

| Name      | Type          | Requirement | Default    | Valid                                                                    | Description                                                                                                                                         |
| --------- | ------------- | ----------- | ---------- | ------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| secret_key | string        | required    |            |  | The secret key of the Google reCAPTCHA service. |
| response | object | optional    | content_type  = `application/json; charset=utf-8`<br />status_code = `400`<br />body = `{"message":"invalid captcha"}` |  | The response of invalid recaptcha token. |
| apis | array | required |  |  | The list of APIs needs to be verified by reCAPTCHA. |

The object definition of apis parameter is

|            | Type   | Default | Description                                                  |
| ---------- | ------ | ------- | ------------------------------------------------------------ |
| path       | string |         | The API path                                                 |
| methods    | string |         | The list of HTTP method                                      |
| param_from | string | header  | The enum of captcha parameter source. Only `header`, `query` are supported. |
| param_name | string | captcha | The name of captcha parameter.                               |

The example configuration of plugin is

```json
{
    "secret_key":"6LeIxAcTAAAAAGGXXXXXXXXXXXXXXXXXXX",
    "apis":[
        {
            "path":"/login",
            "methods":[ "POST" ],
            "param_from":"header",
            "param_name":"captcha"
        },
        {
            "path":"/users/*/active",
            "methods":[ "POST" ],
            "param_from":"query",
            "param_name":"captcha"
        }
    ],
    "response":{
        "content_type":"application/json; charset=utf-8",
        "body":"{\"message\":\"invalid captcha\"}\n",
        "status_code":400
    }
}
```

## How To Enable

Here's an example, enable this plugin on the specified route:

```shell
curl -i http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/users",
    "plugins": {
        "recaptcha": {
            "secret_key":"6LeIxAcTAAAAAGGXXXXXXXXXXXXXXXXXXX",
            "apis":[
                {
                    "path":"/users/self/update",
                    "methods":[ "POST" ],
                    "param_from":"header",
                    "param_name":"captcha"
                },
                {
                    "path":"/users/*/active",
                    "methods":[ "POST" ],
                    "param_from":"query",
                    "param_name":"captcha"
                }
            ],
            "response":{
                "content_type":"application/json; charset=utf-8",
                "body":"{\"message\":\"invalid captcha\"}\n",
                "status_code":400
            }
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```

Here's an example, enable this plugin on the global rule:

```shell
curl -i http://127.0.0.1:9080/apisix/admin/global_rules/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "plugins": {
        "recaptcha": {
            "secret_key":"6LeIxAcTAAAAAGGXXXXXXXXXXXXXXXXXXX",
            "apis":[
                {
                    "path":"/login",
                    "methods":[ "POST" ],
                    "param_from":"header",
                    "param_name":"captcha"
                },
                {
                    "path":"/users/*/active",
                    "methods":[ "POST" ],
                    "param_from":"query",
                    "param_name":"captcha"
                }
            ],
            "response":{
                "content_type":"application/json; charset=utf-8",
                "body":"{\"message\":\"invalid captcha\"}\n",
                "status_code":400
            }
        }
    }
}'
```

## Test Plugin

Use curl to access:

```shell
curl -X POST 'http://127.0.0.1:9080/login'
{"message":"invalid captcha"}

curl -X POST 'http://127.0.0.1:9080/login' -H 'captcha: the_invalid_captcha'
{"message":"invalid captcha"}
```

## Disable Plugin

When you want to disable this plugin, it is very simple,
you can delete the corresponding JSON configuration in the plugin configuration,
no need to restart the service, it will take effect immediately:

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/users",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```

```shell
curl http://127.0.0.1:9080/apisix/admin/global_rules/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "plugins": {
    }
}'
```

This plugin has been disabled now. It works for other plugins.
