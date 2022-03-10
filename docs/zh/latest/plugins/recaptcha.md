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

## 简介

通过向 Google reCAPTCHA 服务校验客户端传递的验证码来限制对上游服务的访问。插件支持自定义无效校验码的响应体。

## 属性

| Name      | Type          | Requirement | Default    | Valid                                                                    | Description                                                                                                                                         |
| --------- | ------------- | ----------- | ---------- | ------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| secret_key | string        | 必须    |            |  | Google reCAPTCHA 的 secret key |
| parameter_source | string | 可选 | header | | 验证码参数的来源枚举值。当前仅支持 `header`, `query` |
| parameter_name | string | 可选 | captcha | | 验证码参数的名称 |
| response | object | 可选    | content_type  = `application/json; charset=utf-8`<br />status_code = `400`<br />body = `{"message":"invalid captcha"}` |  | 无效验证码的 HTTP 响应体 |

插件的配置如下:

```json
{
    "secret_key":"6LeIxAcTAAAAAGGXXXXXXXXXXXXXXXXXXX",
    "parameter_source": "header",
    "parameter_name": "captcha",
    "response":{
        "content_type":"application/json; charset=utf-8",
        "body":"{\"message\":\"invalid captcha\"}\n",
        "status_code":400
    }
}
```

## 如何启用

下面是一个示例，在指定的 `route` 上开启了 `recaptcha` 插件：

```shell
curl -i http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "plugins": {
        "recaptcha": {
            "secret_key": "6LeIxAcTAAAAAGG-XXXXXXXXXXXXXX",
            "parameter_source": "header",
            "parameter_name": "captcha",
            "response": {
                "content_type": "application/json; charset=utf-8",
                "status_code": 400,
                "body": "{\"message\":\"invalid captcha\"}\n"
            }
        }
    },
    "upstream": {
        "nodes": {
            "127.0.0.1:1980": 1
        },
        "type": "roundrobin"
    },
    "uri": "/login"
}'
```

## 测试插件

使用 `curl` 访问：

```shell
curl -X POST 'http://127.0.0.1:9080/login'
{"message":"invalid captcha"}

curl -X POST 'http://127.0.0.1:9080/login' -H 'captcha: the_invalid_captcha'
{"message":"invalid captcha"}
```

## 禁用插件

想要禁用该插件时很简单，在路由 `plugins` 配置块中删除对应 `JSON` 配置，不需要重启服务，即可立即生效禁用该插件。

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/login",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```
