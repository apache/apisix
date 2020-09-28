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

- [中文](../zh-cn/plugins/hmac-auth.md)

# Summary
- [**Name**](#name)
- [**Attributes**](#attributes)
- [**How To Enable**](#how-to-enable)
- [**Test Plugin**](#test-plugin)
- [**Disable Plugin**](#disable-plugin)


## Name

`hmac-auth` is an authentication plugin that need to work with `consumer`. Add HMAC Authentication to a `service` or `route`.

The `consumer` then adds its key to request header to verify its request.

## Attributes

| Name           | Type          | Requirement | Default       | Valid                                       | Description                                                                                                                                                                                                                                                                   |
| -------------- | ------------- | ----------- | ------------- | ------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| access_key     | string        | required    |               |                                             | Different `consumer` objects should have different values, and it should be unique. If different consumers use the same `access_key`, a request matching exception will occur.                                                                                                |
| secret_key     | string        | required    |               |                                             | Use as a pair with `access_key`.                                                                                                                                                                                                                                              |
| algorithm      | string        | optional    | "hmac-sha256" | ["hmac-sha1", "hmac-sha256", "hmac-sha512"] | Encryption algorithm.                                                                                                                                                                                                                                                         |
| clock_skew     | integer       | optional    | 0           |                                             | The clock skew allowed by the signature in seconds. For example, if the time is allowed to skew by 10 seconds, then it should be set to `10`. especially, `0` means not checking `Date`                                                                                    |
| signed_headers | array[string] | optional    |               |                                             | Restrict the headers that are added to the encrypted calculation. After the specified, the client request can only specify the headers within this range. When this item is empty, all the headers specified by the client request will be added to the encrypted calculation |

## How To Enable

1. set a consumer and config the value of the `hmac-auth` option

```shell
curl http://127.0.0.1:9080/apisix/admin/consumers -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "username": "jack",
    "plugins": {
        "hmac-auth": {
            "access_key": "user-key",
            "secret_key": "my-secret-key",
            "clock_skew": 10,
            "signed_headers": ["User-Agent", "Accept-Language", "x-custom-a"]
        }
    }
}'
```

2. add a Route or add a Service , and enable the `hmac-auth` plugin

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

## Test Plugin

### generate signature:
The calculation formula of the signature is `signature = HMAC-SHAx-HEX(secret_key, signing_string)`. From the formula, it can be seen that in order to obtain the signature, two parameters, `SECRET_KEY` and `signing_STRING`, are required. Where secret_key is configured by the corresponding consumer, the calculation formula of `signing_STRING` is `signing_string = HTTP Method + HTTP URI + canonical_query_string + access_key + Date + signed_headers_string`

1. **HTTP Method** : Refers to the GET, PUT, POST and other request methods defined in the HTTP protocol, and must be in all uppercase.
2. **HTTP URI** : `HTTP URI` requirements must start with "/", those that do not start with "/" need to be added, and the empty path is "/".
3. **Date** : Date in http header(GMT format).
4. **canonical_query_string** :`canonical_query_string` is the result of encoding the `query` in the URL (`query` is the string "key1 = valve1 & key2 = valve2" after the "?" in the URL).
5. **signed_headers_string** :`signed_headers_string` is the result of obtaining the fields specified by the client from the request header and concatenating the strings in order.

> The coding steps are as follows:

* Extract the `query` item in the URL, that is, the string "key1 = valve1 & key2 = valve2" after the "?" in the URL.
* Split the `query` into several items according to the & separator, each item is in the form of key=value or only key.
* Encoding each item after disassembly is divided into the following two situations.

    * When the item has only key, the conversion formula is UriEncode(key) + "=".
    * When the item is in the form of key=value, the conversion formula is in the form of UriEncode(key) + "=" + UriEncode(value). Here value can be an empty string.
    * After converting each item, sort by key in lexicographic order (ASCII code from small to large), and connect them with the & symbol to generate the corresponding canonical_query_string.

> The signed_headers_string generation steps are as follows:

* Obtain the headers specified to be added to the calculation from the request header. For details, please refer to the placement of `SIGNED_HEADERS` in the next section `Use the generated signature to make a request attempt`.
* Take out the headers specified by `SIGNED_HEADERS` in order from the request header, and splice them together in order. After splicing, a `signed_headers_string` is generated.

### Use the generated signature to try the request

**Note: ACCESS_KEY, SIGNATURE, ALGORITHM, DATE, SIGNED_HEADERS respectively represent the corresponding variables**
**Note: SIGNED_HEADERS is the headers specified by the client to join the encryption calculation, multiple separated by semicolons, Example: User-Agent;Accept-Language**

* The signature information is put together in the request header `Authorization` field:

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

* The signature information is separately placed in the request header:

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

## Custom header key

We can customize header key for auth parameters by adding the attribute configuration of the plugin under `plugin_attr` in `conf / config.yaml`.

```yaml
plugin_attr:
  hmac-auth:
    signature_key: X-APISIX-HMAC-SIGNATURE
    algorithm_key: X-APISIX-HMAC-ALGORITHM
    date_key: X-APISIX-DATE
    access_key: X-APISIX-HMAC-ACCESS-KEY
    signed_headers_key: X-APISIX-HMAC-SIGNED-HEADERS
```

**After customizing the header, request example:**

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

## Disable Plugin

When you want to disable the `hmac-auth` plugin, it is very simple,
you can delete the corresponding json configuration in the plugin configuration,
no need to restart the service, it will take effect immediately:

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
