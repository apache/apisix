---
title: hmac-auth
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

## 目录

- [目录](#目录)
- [名字](#名字)
- [属性](#属性)
- [如何启用](#如何启用)
- [测试插件](#测试插件)
  - [签名生成公式](#签名生成公式)
  - [使用生成好的签名进行请求尝试](#使用生成好的签名进行请求尝试)
- [自定义 header 名称](#自定义-header-名称)
- [禁用插件](#禁用插件)
- [签名生成示例](#签名生成示例)

## 名字

`hmac-auth` 是一个认证插件，它需要与 `consumer` 一起配合才能工作。

添加 HMAC Authentication 到一个 `service` 或 `route`。 然后 `consumer` 将其签名添加到请求头以验证其请求。

## 属性

| 名称             | 类型          | 必选项 | 默认值        | 有效值                                      | 描述                                                                                                                                                                                    |
| ---------------- | ------------- | ------ | ------------- | ------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| access_key       | string        | 必须   |               |                                             | 不同的 `consumer` 对象应有不同的值，它应当是唯一的。不同 consumer 使用了相同的 `access_key` ，将会出现请求匹配异常。                                                                    |
| secret_key       | string        | 必须   |               |                                             | 与 `access_key` 配对使用。                                                                                                                                                              |
| algorithm        | string        | 可选   | "hmac-sha256" | ["hmac-sha1", "hmac-sha256", "hmac-sha512"] | 加密算法。                                                                                                                                                                              |
| clock_skew       | integer       | 可选   | 0             |                                             | 签名允许的时间偏移，以秒为单位的计时。比如允许时间偏移 10 秒钟，那么就应设置为 `10`。特别地，`0` 表示不对 `Date` 进行检查。                                                             |
| signed_headers   | array[string] | 可选   |               |                                             | 限制加入加密计算的 headers ，指定后客户端请求只能在此范围内指定 headers ，此项为空时将把所有客户端请求指定的 headers 加入加密计算。如： ["User-Agent", "Accept-Language", "x-custom-a"] |
| keep_headers     | boolean       | 可选   | false         | [ true, false ]                             | 认证成功后的 http 请求中是否需要保留 `X-HMAC-SIGNATURE`、`X-HMAC-ALGORITHM` 和 `X-HMAC-SIGNED-HEADERS` 的请求头。true: 表示保留 http 请求头，false: 表示移除 http 请求头。              |
| encode_uri_param | boolean       | 可选   | true          | [ true, false ]                             | 是否对签名中的 uri 参数进行编码,例如: `params1=hello%2Cworld` 进行了编码，`params2=hello,world` 没有进行编码。true: 表示对签名中的 uri 参数进行编码，false: 不对签名中的 uri 参数编码。 |

## 如何启用

1. 创建一个 consumer 对象，并设置插件 `hmac-auth` 的值。

```shell
curl http://127.0.0.1:9080/apisix/admin/consumers -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "username": "jack",
    "plugins": {
        "hmac-auth": {
            "access_key": "user-key",
            "secret_key": "my-secret-key",
            "clock_skew": 0,
            "signed_headers": ["User-Agent", "Accept-Language", "x-custom-a"]
        }
    }
}'
```

默认 `keep_headers` 为 false，`encode_uri_param` 为 true。

2. 创建 Route 或 Service 对象，并开启 `hmac-auth` 插件。

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/index.html",
    "plugins": {
        "hmac-auth": {}
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "39.97.63.215:80": 1
        }
    }
}'
```

## 测试插件

### 签名生成公式

签名的计算公式为 `signature = HMAC-SHAx-HEX(secret_key, signing_string)`，从公式可以看出，想要获得签名需要得到 `secret_key` 和 `signing_string` 两个参数。其中 `secret_key` 为对应 consumer 所配置的， `signing_string` 的计算公式为 `signing_string = HTTP Method + \n + HTTP URI + \n + canonical_query_string + \n + access_key + \n + Date + \n + signed_headers_string`。

1. **HTTP Method**：指 HTTP 协议中定义的 GET、PUT、POST 等请求方法，必须使用全大写的形式。
2. **HTTP URI**：要求必须以“/”开头，不以“/”开头的需要补充上，空路径为“/”。
3. **Date**：请求头中的 Date （ GMT 格式 ）。
4. **canonical_query_string**：是对于 URL 中的 query（ query 即 URL 中 ? 后面的 key1=valve1&key2=valve2 字符串）进行编码后的结果。
5. **signed_headers_string**：是从请求头中获取客户端指定的字段，并按顺序拼接字符串的结果。

> canonical_query_string 编码步骤如下：

* 提取 URL 中的 query 项，即 URL 中 ? 后面的 key1=valve1&key2=valve2 字符串。
* 将 query 根据&分隔符拆开成若干项，每一项是 key=value 或者只有 key 的形式。
* 根据 uri 参数是否编码，有下面两种情况：
* `encode_uri_param` 为 true 时：
  * 对拆开后的每一项进行编码处理，分以下两种情况:
  * 当该项只有 key 时，转换公式为 url_encode(key) + "=" 的形式。
  * 当该项是 key=value 的形式时，转换公式为 url_encode(key) + "=" + url_encode(value) 的形式。这里 value 可以是空字符串。
  * 将每一项转换后，以 key 按照字典顺序（ ASCII 码由小到大）排序，并使用 & 符号连接起来，生成相应的 canonical_query_string 。
* `encode_uri_param` 为 false 时:
  * 对拆开后的每一项进行编码处理，分以下两种情况:
  * 当该项只有 key 时，转换公式为 key + "=" 的形式。
  * 当该项是 key=value 的形式时，转换公式为 key + "=" + value 的形式。这里 value 可以是空字符串。
  * 将每一项转换后，以 key 按照字典顺序（ ASCII 码由小到大）排序，并使用 & 符号连接起来，生成相应的 canonical_query_string 。

> signed_headers_string 生成步骤如下：

* 从请求头中获取指定加入计算的 headers ，具体请参考下节 `使用生成好的签名进行请求尝试` 中的 `SIGNED_HEADERS` 放置的位置。
* 从请求头中按顺序取出 `SIGNED_HEADERS` 指定的 headers ，并按顺序用`name:value`方式拼接起来，拼接完后就生成了 `signed_headers_string` 。

```plain
HeaderKey1 + ":" + HeaderValue1 + "\n"\+
HeaderKey2 + ":" + HeaderValue2 + "\n"\+
...
HeaderKeyN + ":" + HeaderValueN + "\n"
```

**签名字符串拼接示例**

以下面请求为例：

```shell
$ curl -i http://127.0.0.1:9080/index.html?name=james&age=36 \
-H "X-HMAC-SIGNED-HEADERS: User-Agent;x-custom-a" \
-H "x-custom-a: test" \
-H "User-Agent: curl/7.29.0"
```

根据`签名生成公式`生成的 `signing_string` 为：

```plain
"GET
/index.html
age=36&name=james
user-key
Tue, 19 Jan 2021 11:33:20 GMT
User-Agent:curl/7.29.0
x-custom-a:test
"
```

注意：最后一个请求头也需要 + `\n`。

**生成签名**

使用 Python 来生成签名 `SIGNATURE`：

```python
import hashlib
import hmac
import base64

secret = bytes('my-secret-key', 'utf-8')
message = bytes("""GET
/index.html
age=36&name=james
user-key
Tue, 19 Jan 2021 11:33:20 GMT
User-Agent:curl/7.29.0
x-custom-a:test
""", 'utf-8')

hash = hmac.new(secret, message, hashlib.sha256)

# to lowercase base64
print(base64.b64encode(hash.digest()))
```

| Type      | Hash                                         |
| --------- | -------------------------------------------- |
| SIGNATURE | 8XV1GB7Tq23OJcoz6wjqTs4ZLxr9DiLoY4PxzScWGYg= |

### 使用生成好的签名进行请求尝试

```shell
$ curl -i "http://127.0.0.1:9080/index.html?name=james&age=36" \
-H "X-HMAC-SIGNATURE: 8XV1GB7Tq23OJcoz6wjqTs4ZLxr9DiLoY4PxzScWGYg=" \
-H "X-HMAC-ALGORITHM: hmac-sha256" \
-H "X-HMAC-ACCESS-KEY: user-key" \
-H "Date: Tue, 19 Jan 2021 11:33:20 GMT" \
-H "X-HMAC-SIGNED-HEADERS: User-Agent;x-custom-a" \
-H "x-custom-a: test" \
-H "User-Agent: curl/7.29.0"

HTTP/1.1 200 OK
Content-Type: text/html; charset=utf-8
Transfer-Encoding: chunked
Connection: keep-alive
Date: Tue, 19 Jan 2021 11:33:20 GMT
Server: APISIX/2.2
......
```

**下面是签名信息的两种组装形式**

* 签名信息拼一起放到请求头 `Authorization` 字段中：

```shell
$ curl http://127.0.0.1:9080/index.html -H 'Authorization: hmac-auth-v1# + ACCESS_KEY + # + base64_encode(SIGNATURE) + # + ALGORITHM + # + DATE + # + SIGNED_HEADERS' -i
HTTP/1.1 200 OK
Content-Type: text/html
Content-Length: 13175
...
Accept-Ranges: bytes

<!DOCTYPE html>
<html lang="cn">
...
```

- 签名信息分开分别放到请求头：

```shell
$ curl http://127.0.0.1:9080/index.html -H 'X-HMAC-SIGNATURE: base64_encode(SIGNATURE)' -H 'X-HMAC-ALGORITHM: ALGORITHM' -H 'Date: DATE' -H 'X-HMAC-ACCESS-KEY: ACCESS_KEY' -H 'X-HMAC-SIGNED-HEADERS: SIGNED_HEADERS' -i
HTTP/1.1 200 OK
Content-Type: text/html
Content-Length: 13175
...
Accept-Ranges: bytes

<!DOCTYPE html>
<html lang="cn">
```

**注:**

1. **ACCESS_KEY, SIGNATURE, ALGORITHM, DATE, SIGNED_HEADERS 分别代表对应的变量**
2. **SIGNED_HEADERS 为客户端指定的加入加密计算的 headers。若存在多个 headers 需以 ";" 分割：`x-custom-header-a;x-custom-header-b`**
3. **SIGNATURE 需要使用 base64 进行加密：`base64_encode(SIGNATURE)`**

## 自定义 header 名称

我们可以在 `conf/config.yaml` 中，`plugin_attr` 下添加插件的属性配置来自定义参数 header 名称。

```yaml
plugin_attr:
  hmac-auth:
    signature_key: X-APISIX-HMAC-SIGNATURE
    algorithm_key: X-APISIX-HMAC-ALGORITHM
    date_key: X-APISIX-DATE
    access_key: X-APISIX-HMAC-ACCESS-KEY
    signed_headers_key: X-APISIX-HMAC-SIGNED-HEADERS
```

**自定义 header 后，请求示例：**

```shell
$ curl http://127.0.0.1:9080/index.html -H 'X-APISIX-HMAC-SIGNATURE: base64_encode(SIGNATURE)' -H 'X-APISIX-HMAC-ALGORITHM: ALGORITHM' -H 'X-APISIX-DATE: DATE' -H 'X-APISIX-HMAC-ACCESS-KEY: ACCESS_KEY' -H 'X-APISIX-HMAC-SIGNED-HEADERS: SIGNED_HEADERS' -i
HTTP/1.1 200 OK
Content-Type: text/html
Content-Length: 13175
...
Accept-Ranges: bytes

<!DOCTYPE html>
<html lang="cn">
```

## 禁用插件

当你想去掉 `hmac-auth` 插件的时候，很简单，在插件的配置中把对应的 `json` 配置删除即可，无须重启服务，即刻生效：

```shell
$ curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/index.html",
    "plugins": {},
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "39.97.63.215:80": 1
        }
    }
}'
```

## 签名生成示例

以 HMAC SHA256 为例，介绍一下各种语言的签名生成示例。需要注意各种语言中对签名字符串的换行符的处理方式，这很容易导致出现 `{"message":"Invalid signature"}` 的问题。

示例入参说明:

| Variable | Value                    |
| -------- | ------------------------ |
| secret   | this is secret key       |
| message  | this is signature string |

示例出参说明：

| Type   | Hash                                                             |
| ------ | ---------------------------------------------------------------- |
| hexit  | ad1b76c7e5054009380edca35d3f36cc5b6f45c82ee02ea3af64197ebddb9345 |
| base64 | rRt2x+UFQAk4DtyjXT82zFtvRcgu4C6jr2QZfr3bk0U=                     |

具体代码请参考：[**HMAC Generate Signature Examples**](../examples/plugins-hmac-auth-generate-signature.md)
