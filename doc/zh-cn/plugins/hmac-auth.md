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

- [English](../../plugins/hmac-auth.md)

# 目录
- [**名字**](#名字)
- [**属性**](#属性)
- [**如何启用**](#如何启用)
- [**测试插件**](#测试插件)
- [**禁用插件**](#禁用插件)


## 名字

`hmac-auth` 是一个认证插件，它需要与 `consumer` 一起配合才能工作。

添加 HMAC Authentication 到一个 `service` 或 `route`。 然后 `consumer` 将其签名添加到请求头以验证其请求。

## 属性

|属性名         |是否可选 | 默认值 |描述|
|---------     |--------|-----------|-----------|
| `access_key` | 必须 | 无 | 不同的 `consumer` 对象应有不同的值，它应当是唯一的。不同 consumer 使用了相同的 `access_key` ，将会出现请求匹配异常。|
| `secret_key`| 必须 | 无 | 与 `access_key` 配对使用。|
| `algorithm` | 可选 | hmac-sha256 | 加密算法。目前支持 `hmac-sha1`, `hmac-sha256` 和 `hmac-sha512`。|
| `clock_skew`| 可选 | 300 | 签名允许的时间偏移，以秒为单位的计时。比如允许时间偏移 10 秒钟，那么就应设置为 `10`。特别地，`0` 表示不对 `timestamp` 进行检查。|

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
            "clock_skew": 10
        }
    }
}'
```

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

签名的计算公式为 `signature = HMAC-SHAx-HEX(secret_key, signning_string)`，从公式可以看出，想要获得签名需要得到 `secret_key` 和 `signning_string` 两个参数。其中 `secret_key` 为对应 consumer 所配置的， `signning_string` 的计算公式为 `signning_string = HTTP Method + HTTP URI + canonical_query_string + HTTP BODY + access_key + timestamp + secret_key`

1. **HTTP Method**：指 HTTP 协议中定义的 GET、PUT、POST 等请求方法，必须使用全大写的形式。
2. **HTTP URI**：要求必须以“/”开头，不以“/”开头的需要补充上，空路径为“/”。
3. **canonical_query_string**：是对于 URL 中的 query（ query 即 URL 中 ? 后面的 key1=valve1&key2=valve2 字符串）进行编码后的结果。

> canonical_query_string 编码步骤如下：

* 提取 URL 中的 query 项，即 URL 中 ? 后面的 key1=valve1&key2=valve2 字符串。
* 将 query 根据&分隔符拆开成若干项，每一项是 key=value 或者只有 key 的形式。
* 对拆开后的每一项进行编码处理，分以下两种情况:
  * 当该项只有 key 时，转换公式为 url_encode(key) + "=" 的形式。
  * 当该项是 key=value 的形式时，转换公式为 url_encode(key) + "=" + url_encode(value) 的形式。这里 value 可以是空字符串。
  * 将每一项转换后，以 key 按照字典顺序（ ASCII 码由小到大）排序，并使用 & 符号连接起来，生成相应的 canonical_query_string 。



### 使用生成好的签名进行请求尝试

**注： ACCESS_KEY,SIGNATURE,ALGORITHM,TIMESTAMP 分别代表对应的变量**

* 签名信息拼一起放到请求头 `Authorization` 字段中：

```shell
$ curl http://127.0.0.1:9080/index.html -H 'Authorization: hmac-auth-v1# + ACCESS_KEY + # + base64_encode(SIGNATURE) + # + ALGORITHM + # + TIMESTAMP' -i
HTTP/1.1 200 OK
Content-Type: text/html
Content-Length: 13175
...
Accept-Ranges: bytes

<!DOCTYPE html>
<html lang="cn">
...
```

* 签名信息分开分别放到请求头：

```shell
$ curl http://127.0.0.1:9080/index.html -H 'X-HMAC-SIGNATURE: base64_encode(SIGNATURE)' -H 'X-HMAC-ALGORITHM: ALGORITHM' -H 'X-HMAC-TIMESTAMP: TIMESTAMP' -H 'X-HMAC-ACCESS-KEY: ACCESS_KEY' -i
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
