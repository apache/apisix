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

- [English](../../plugins/proxy-cache.md)

# proxy-cache

代理缓存插件，该插件提供缓存后端响应数据的能力，它可以和其他插件一起使用。该插件支持基于磁盘的缓存，未来也会支持基于内存的缓存。目前可以根据响应码、请求 Method 来指定需要缓存的数据，另外也可以通过 no_cache 和 cache_bypass 配置更复杂的缓存策略。

基于磁盘的缓存需要注意：
1. 不能动态配置缓存的过期时间，只能通过后端服务响应头 Expires 或 Cache-Control 来设置过期时间，如果后端响应头中没有 Expires 或 Cache-Control，那么 APISIX 将默认只缓存10秒钟
2. 如果后端服务不可用， APISIX 将返回502或504，那么502或504将被缓存10秒钟

### 参数

|名称    |必须|类型|描述|
|------- |-----|------|------|
|cache_zone|是|string|指定使用哪个缓存区域，不同的缓存区域可以配置不同的路径，在conf/config.yaml文件中可以预定义使用的缓存区域|
|cache_key|是|array[string]|缓存key，可以使用变量。例如：["$host", "$uri", "-cache-id"]|
|cache_bypass|否|array[string]|是否跳过缓存检索，即不在缓存中查找数据，可以使用变量，需要注意当此参数的值不为空或非'0'时将会跳过缓存的检索。例如：["$arg_bypass"]|
|cache_method|否|array[string]|根据请求method决定是否需要缓存|
|cache_http_status|否|array[integer]|根据响应码决定是否需要缓存|
|hide_cache_headers|否|boolean|是否将 Expires 和 Cache-Control 响应头返回给客户端，默认为 false|
|no_cache|否|array[string]|是否缓存数据，可以使用变量，需要注意当此参数的值不为空或非'0'时将不会缓存数据。|

注：变量以$开头，也可以使用变量和字符串的结合，但是需要以数组的形式分开写，最终变量被解析后会和字符串拼接在一起。

### 示例

#### 启用插件

示例1：为特定路由启用 `proxy-cache` 插件：

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "plugins": {
        "proxy-cache": {
           "cache_zone": "disk_cache_one",
           "cache_key":  ["$uri", "-cache-id"],
           "cache_bypass": ["$arg_bypass"],
           "cache_method": ["GET"],
           "cache_http_status": [200],
           "hide_cache_headers": true,
           "no_cache": ["$arg_test"]
        }
    },
    "upstream": {
        "nodes": {
            "127.0.0.1:1999": 1
        },
        "type": "roundrobin"
    },
    "uri": "/hello"
}'
```

测试：

```shell
$ curl http://127.0.0.1:9080/hello -i
HTTP/1.1 200 OK
Content-Type: application/octet-stream
Content-Length: 6
Connection: keep-alive
Server: APISIX web server
Date: Tue, 03 Mar 2020 10:45:36 GMT
Last-Modified: Tue, 03 Mar 2020 10:36:38 GMT
Apisix-Cache-Status: MISS

hello
```

> http status 返回`200`并且响应头中包含`Apisix-Cache-Status`，表示该插件已启用。

示例2：验证文件是否被缓存，再次请求上边的地址：

测试：

```shell
$ curl http://127.0.0.1:9080/hello -i
HTTP/1.1 200 OK
Content-Type: application/octet-stream
Content-Length: 6
Connection: keep-alive
Server: APISIX web server
Date: Tue, 03 Mar 2020 11:14:46 GMT
Last-Modified: Thu, 20 Feb 2020 14:21:41 GMT
Apisix-Cache-Status: HIT

hello
```

> 响应头  Apisix-Cache-Status 值变为了 HIT，说明文件已经被缓存

示例3：如何清理缓存的文件，只需要指定请求的 method 为 PURGE：

测试：

```shell
$ curl -i http://127.0.0.1:9080/hello -X PURGE
HTTP/1.1 200 OK
Date: Tue, 03 Mar 2020 11:17:35 GMT
Content-Type: text/plain
Transfer-Encoding: chunked
Connection: keep-alive
Server: APISIX web server
```

> 响应码为200即表示删除成功，如果文件未找到将返回404

#### 禁用插件

移除插件配置中相应的 JSON 配置可立即禁用该插件，无需重启服务：

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/hello",
    "plugins": {},
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1999": 1
        }
    }
}'
```

这时该插件已被禁用。
