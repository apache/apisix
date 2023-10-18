---
title: hmac-auth
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - HMAC Authentication
  - hmac-auth
description: 本文介绍了关于 Apache APISIX `hmac-auth` 插件的基本信息及使用方法。
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

## 描述

`hmac-auth` 插件可以将 [HMAC authentication](https://en.wikipedia.org/wiki/HMAC) 添加到 Route 或者 Service。

该插件需要和 Consumer 一起使用，API 的使用者必须将密匙添加到请求头中以验证其请求。

## 属性

| 名称             | 类型          | 必选项 | 默认值        | 有效值                                      | 描述                                                                                                                                                                                      |
| ---------------- | ------------- | ------ | ------------- | ------------------------------------------| ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| access_key       | string        | 是   |               |                                             |  Consumer 的 `access_key` 必须是唯一的。如果不同 Consumer 使用了相同的 `access_key` ，将会出现请求匹配异常。                                                                                   |
| secret_key       | string        | 是   |               |                                             | 与 `access_key` 配对使用。该字段支持使用 [APISIX Secret](../terminology/secret.md) 资源，将值保存在 Secret Manager 中。                                                |
| algorithm        | string        | 否   | "hmac-sha256" | ["hmac-sha1", "hmac-sha256", "hmac-sha512"] | 可以使用的加密算法。                                                                                                                                                                        |
| clock_skew       | integer       | 否   | 0             |                                             | 签名允许的时间偏移（以秒为单位）。比如允许时间偏移 10 秒钟，那么就应设置为 `10`。如果将其设置为 `0`，则表示表示跳过日期检查。                                                                      |
| signed_headers   | array[string] | 否   |               |                                             | 要在加密计算中使用的 headers 列表。指定后客户端请求只能在此范围内指定 headers，如果未指定，就会在所有客户端请求指定的 headers 加入加密计算。如： ["User-Agent", "Accept-Language", "x-custom-a"]。  |
| keep_headers     | boolean       | 否   | false         | [ true, false ]                             | 当设置为 `true` 时，认证成功后的 HTTP 请求中则会保留 `X-HMAC-SIGNATURE`、`X-HMAC-ALGORITHM` 和 `X-HMAC-SIGNED-HEADERS` 的请求头。否则将移除 HTTP 请求头。                                       |
| encode_uri_params| boolean       | 否   | true          | [ true, false ]                             | 当设置为 `true` 时，对签名中的 URI 参数进行编码。例如：`params1=hello%2Cworld` 进行了编码，`params2=hello,world` 没有进行编码。设置为 `false` 时则不对签名中的 URI 参数编码。                     |
| validate_request_body | boolean  | 否   | false         | [ true, false ]                             | 当设置为 `true` 时，对请求 body 做签名校验。                                                                                                                                                 |
| max_req_body     | integer       | 否   | 512 * 1024    |                                             | 最大允许的 body 大小。                                                                                                                                                                      |

注意：schema 中还定义了 `encrypt_fields = {"secret_key"}`，这意味着该字段将会被加密存储在 etcd 中。具体参考 [加密存储字段](../plugin-develop.md#加密存储字段)。

## 启用插件

首先，我们需要在 Consumer 中启用该插件，如下所示：

```shell
curl http://127.0.0.1:9180/apisix/admin/consumers \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

<!--
你也可以通过 [APISIX Dashboard](/docs/dashboard/USER_GUIDE) 的 Web 界面完成操作。

![create a consumer](https://raw.githubusercontent.com/apache/apisix/master/docs/assets/images/plugin/hmac-auth-1.png)

![enable hmac plugin](https://raw.githubusercontent.com/apache/apisix/master/docs/assets/images/plugin/hmac-auth-2.png)
-->

然后就可以在 Route 或 Service 中启用插件，如下所示：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/index.html",
    "plugins": {
        "hmac-auth": {}
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```

## 签名算法详解

### 签名生成公式

在使用 `hmac-auth` 插件时，会涉及到签名。签名的计算公式为 `signature = HMAC-SHAx-HEX(secret_key, signing_string)`。

为了生成签名需要两个参数：`secret_key` 和 `signing_string`。其中 `secret_key` 由对应 Consumer 配置，`signing_string` 的计算公式为 `signing_string = HTTP Method + \n + HTTP URI + \n + canonical_query_string + \n + access_key + \n + Date + \n + signed_headers_string`。以下是对计算公式中各个字段的释义：

- **HTTP Method**：指 HTTP 协议中定义的 GET、PUT、POST 等请求方法，必须使用全大写的形式。
- **HTTP URI**：HTTP URI。必须以 `/` 开头，`/` 表示空路径。
- **Date**：请求头中的日期（GMT 格式）。
- **canonical_query_string**：对 URL 中的 query（query 即 URL 中 `?` 后面的 `key1=valve1&key2=valve2` 字符串）进行编码后的结果。
- **signed_headers_string**：从请求头中获取客户端指定的字段，并按顺序拼接字符串的结果。

:::tip 提示

- 如果 `signing_string` 中的任意一项不存在，则需要使用一个空字符串代替。

- 由于签名计算时，会区分大小写字母，在使用时，请规范其参数命名。

:::

**生成 `canonical_query_string` 的算法描述如下：**

1. 提取 URL 中的 query 项。
2. 使用 `&` 作为分隔符，将 query 拆分成键值对。
3. 如果 `encode_uri_params` 为 `true` 时：

    - 当该项有 `key` 时，转换公式为 `url_encode(key) + "="`。
    - 当该项同时有 `key` 和 `value` 时，转换公式为 `url_encode(key) + "=" + url_encode(value)` 。此处 `value` 可以是空字符串。
    - 将每一项转换后，以 `key` 按照字典顺序（ASCII 码由小到大）排序，并使用 `&` 符号连接起来，生成相应的 `canonical_query_string` 。

4. 如果 `encode_uri_params` 为 `false` 时：

    - 当该项只有 `key` 时，转换公式为 `key + "="` 。
    - 当该项同时有 `key` 和 `value` 时，转换公式为 `key + "=" + value` 。此处 `value` 可以是空字符串。
    - 将每一项转换后，以 `key` 按照字典顺序（ASCII 码由小到大）排序，并使用 `&` 符号连接起来，生成相应的 `canonical_query_string`。

**生成 `signed_headers_string` 的算法如下：**

1. 从请求头中获取指定的 headers 加入计算中。
2. 从请求头中按顺序取出 `SIGNED_HEADERS` 指定的 headers，并按顺序用 `name:value` 方式拼接起来，拼接完后就生成了 `signed_headers_string`。

```plain
HeaderKey1 + ":" + HeaderValue1 + "\n"\+
HeaderKey2 + ":" + HeaderValue2 + "\n"\+
...
HeaderKeyN + ":" + HeaderValueN + "\n"
```

### 签名生成公式过程详解

接下来，我们将以下述请求为例，为你介绍签名生成公式的具体计算过程：

```shell
curl -i http://127.0.0.1:9080/index.html?name=james&age=36 \
-H "X-HMAC-SIGNED-HEADERS: User-Agent;x-custom-a" \
-H "x-custom-a: test" \
-H "User-Agent: curl/7.29.0"
```

1. 上文请求默认的 HTTP Method 是 GET，得到 `signing_string` 为：

```plain
"GET"
```

2. 请求的 URI 是 `/index.html`，根据 HTTP Method + \n + HTTP URI 得到 `signing_string` 为：

```plain
"GET
/index.html"
```

3. URL 中的 query 项是 `name=james&age=36`，假设 `encode_uri_params` 为 false，根据 `canonical_query_string` 的算法，重点是对 `key` 进行字典排序，得到 `age=36&name=james`；根据 HTTP Method + \n + HTTP URI + \n + canonical_query_string 得到 `signing_string` 为：

```plain
"GET
/index.html
age=36&name=james"
```

4. access_key 是 `user-key`，根据 HTTP Method + \n + HTTP URI + \n + canonical_query_string + \n + access_key 得到 `signing_string` 为：

```plain
"GET
/index.html
age=36&name=james
user-key"
```

5. Date 是指 GMT 格式的日期，形如 `Tue, 19 Jan 2021 11:33:20 GMT`, 根据 HTTP Method + \n + HTTP URI + \n + canonical_query_string + \n + access_key + \n + Date 得到 `signing_string` 为：

```plain
"GET
/index.html
age=36&name=james
user-key
Tue, 19 Jan 2021 11:33:20 GMT"
```

6. `signed_headers_string` 用来制定参与到签名的 headers，在上面示例中包括 `User-Agent: curl/7.29.0` 和 `x-custom-a: test`。

根据 HTTP Method + \n + HTTP URI + \n + canonical_query_string + \n + access_key + \n + Date + \n + signed_headers_string + `\n`，得到完整的 `signing_string` 为：

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

### Body 校验

当 `validate_request_body` 设置为 `true` 时，插件将计算请求 body 的 `hmac-sha` 值，并与请求 headers 中的 `X-HMAC-DIGEST` 的值进行校验。

```
X-HMAC-DIGEST: base64(hmac-sha(<body>))
```

如果没有请求 body，你可以将 `X-HMAC-DIGEST` 的值设置为空字符串的 HMAC-SHA。

:::note 注意

当开启 body 校验时，为了计算请求 body 的 `hmac-sha` 值，该插件会把 body 加载到内存中，在请求 body 较大的情况下，可能会造成较高的内存消耗。

为了避免这种情况，你可以通过设置 `max_req_body`（默认值是 512KB）配置项来配置最大允许的 body 大小，body 超过此大小的请求会被拒绝。

:::

## 测试插件

假设当前请求为：

```shell
curl -i http://127.0.0.1:9080/index.html?name=james&age=36 \
-H "X-HMAC-SIGNED-HEADERS: User-Agent;x-custom-a" \
-H "x-custom-a: test" \
-H "User-Agent: curl/7.29.0"
```

通过以下 Python 代码为上述请求生成签名 `SIGNATURE`：

```python
import base64
import hashlib
import hmac

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

你也可以参考 [Generating HMAC signatures](../../../en/latest/examples/plugins-hmac-auth-generate-signature.md) 了解如何使用不同的编程语言生成签名。

签名生成后，你可以通过以下示例使用生成的签名发起请求：

```shell
curl -i "http://127.0.0.1:9080/index.html?name=james&age=36" \
-H "X-HMAC-SIGNATURE: 8XV1GB7Tq23OJcoz6wjqTs4ZLxr9DiLoY4PxzScWGYg=" \
-H "X-HMAC-ALGORITHM: hmac-sha256" \
-H "X-HMAC-ACCESS-KEY: user-key" \
-H "Date: Tue, 19 Jan 2021 11:33:20 GMT" \
-H "X-HMAC-SIGNED-HEADERS: User-Agent;x-custom-a" \
-H "x-custom-a: test" \
-H "User-Agent: curl/7.29.0"
```

```shell
HTTP/1.1 200 OK
Content-Type: text/html; charset=utf-8
Transfer-Encoding: chunked
Connection: keep-alive
Date: Tue, 19 Jan 2021 11:33:20 GMT
Server: APISIX/2.2
......
```

你也可以将签名放到请求头 `Authorization` 字段中：

```shell
curl http://127.0.0.1:9080/index.html \
-H 'Authorization: hmac-auth-v1# + ACCESS_KEY + # + base64_encode(SIGNATURE) + # + ALGORITHM + # + DATE + # + SIGNED_HEADERS' -i
```

```shell
HTTP/1.1 200 OK
Content-Type: text/html
Content-Length: 13175
...
Accept-Ranges: bytes

<!DOCTYPE html>
<html lang="cn">
...
```

还可以将签名单独放在另一个请求头中：

```shell
curl http://127.0.0.1:9080/index.html \
-H 'X-HMAC-SIGNATURE: base64_encode(SIGNATURE)' \
-H 'X-HMAC-ALGORITHM: ALGORITHM' \
-H 'Date: DATE' \
-H 'X-HMAC-ACCESS-KEY: ACCESS_KEY' \
-H 'X-HMAC-SIGNED-HEADERS: SIGNED_HEADERS' -i
```

```shell
HTTP/1.1 200 OK
Content-Type: text/html
Content-Length: 13175
...
Accept-Ranges: bytes

<!DOCTYPE html>
<html lang="cn">
```

:::note 注意

1. ACCESS_KEY、SIGNATURE、ALGORITHM、DATE、SIGNED_HEADERS 分别代表对应的变量。
2. SIGNED_HEADERS 为客户端指定的加入加密计算的 headers。若存在多个 headers 需以 `;` 分割，例如：`x-custom-header-a;x-custom-header-b`。
3. SIGNATURE 需要使用 base64 进行加密：`base64_encode(SIGNATURE)`。

:::

### 自定义 header 名称

除了配置签名外，你还可以在配置文件（`conf/config.yaml`）中的 `plugin_attr` 配置项下，添加 `hmac-auth` 插件的属性来自定义参数 header 名称。如下所示：

```yaml title="conf/config.yaml"
plugin_attr:
  hmac-auth:
    signature_key: X-APISIX-HMAC-SIGNATURE
    algorithm_key: X-APISIX-HMAC-ALGORITHM
    date_key: X-APISIX-DATE
    access_key: X-APISIX-HMAC-ACCESS-KEY
    signed_headers_key: X-APISIX-HMAC-SIGNED-HEADERS
    body_digest_key: X-APISIX-HMAC-BODY-DIGEST
```

配置完成后，你可以使用自定义的 header 发起请求。

```shell
curl http://127.0.0.1:9080/index.html \
-H 'X-APISIX-HMAC-SIGNATURE: base64_encode(SIGNATURE)' \
-H 'X-APISIX-HMAC-ALGORITHM: ALGORITHM' \
-H 'X-APISIX-DATE: DATE' \
-H 'X-APISIX-HMAC-ACCESS-KEY: ACCESS_KEY' \
-H 'X-APISIX-HMAC-SIGNED-HEADERS: SIGNED_HEADERS' \
-H 'X-APISIX-HMAC-BODY-DIGEST: BODY_DIGEST' -i
```

```
HTTP/1.1 200 OK
Content-Type: text/html
Content-Length: 13175
...
Accept-Ranges: bytes

<!DOCTYPE html>
<html lang="cn">
```

## 删除插件

当你需要删除该插件时，可以通过以下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/index.html",
    "plugins": {},
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```
