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

| 名称               | 类型           | 必选项 | 默认值                    | 有效值                                                                          | 描述                                                                                                                               |
| ------------------ | -------------- | ------ | ------------------------- | ------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| cache_zone         | string         | 可选   |        disk_cache_one     |                                                                                 | 指定使用哪个缓存区域，不同的缓存区域可以配置不同的路径，在 conf/config.yaml 文件中可以预定义使用的缓存区域。当不使用默认值时，指定的缓存区域与 conf/config.yaml 文件中预定义的缓存区域不一致，缓存无效。   |
| cache_key          | array[string]  | 可选   | ["$host", "$request_uri"] |                                                                                 | 缓存key，可以使用变量。例如：["$host", "$uri", "-cache-id"]                                                                        |
| cache_bypass       | array[string]  | 可选   |                           |                                                                                 | 是否跳过缓存检索，即不在缓存中查找数据，可以使用变量，需要注意当此参数的值不为空或非'0'时将会跳过缓存的检索。例如：["$arg_bypass"] |
| cache_method       | array[string]  | 可选   | ["GET", "HEAD"]           | ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD","OPTIONS", "CONNECT", "TRACE"] | 根据请求method决定是否需要缓存                                                                                                     |
| cache_http_status  | array[integer] | 可选   | [200, 301, 404]           | [200, 599]                                                                      | 根据响应码决定是否需要缓存                                                                                                         |
| hide_cache_headers | boolean        | 可选   | false                     |                                                                                 | 是否将 Expires 和 Cache-Control 响应头返回给客户端                                                                                 |
| no_cache           | array[string]  | 可选   |                           |                                                                                 | 是否缓存数据，可以使用变量，需要注意当此参数的值不为空或非'0'时将不会缓存数据                                                      |

注：变量以$开头，也可以使用变量和字符串的结合，但是需要以数组的形式分开写，最终变量被解析后会和字符串拼接在一起。

在 `conf/config.yaml` 文件中的配置示例:

```yaml
proxy_cache:                       # 代理缓存配置
    cache_ttl: 10s                 # 如果上游未指定缓存时间，则为默认缓存时间
    zones:                         # 缓存的参数
    - name: disk_cache_one         # 缓存名称(缓存区域)，管理员可以通过admin api中的 cache_zone 字段指定要使用的缓存区域
      memory_size: 50m             # 共享内存的大小，用于存储缓存索引
      disk_size: 1G                # 磁盘大小，用于存储缓存数据
      disk_path: "/tmp/disk_cache_one" # 存储缓存数据的路径
      cache_levels: "1:2"          # 缓存的层次结构级别
```

### 示例

#### 启用插件

示例一：cache_zone 参数默认为 `disk_cache_one`

1、为特定路由启用 `proxy-cache` 插件：

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "plugins": {
        "proxy-cache": {
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

> http status 返回`200`并且响应头中包含 `Apisix-Cache-Status`，表示该插件已启用。

2、验证数据是否被缓存，再次请求上边的地址：

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

> 响应头  Apisix-Cache-Status 值变为了 HIT，说明数据已经被缓存

示例二：自定义 cache_zone 参数为 `disk_cache_two`

1、在 `conf/config.yaml` 文件中的指定缓存区域等信息:

```yaml
proxy_cache:
    cache_ttl: 10s
    zones:
    - name: disk_cache_two
      memory_size: 50m
      disk_size: 1G
      disk_path: "/tmp/disk_cache_one"
      cache_levels: "1:2"
```

2、为特定路由启用 `proxy-cache` 插件：

```shell
$ curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "plugins": {
        "proxy-cache": {
            "cache_zone": "disk_cache_two",
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

> http status 返回`200`并且响应头中包含 `Apisix-Cache-Status`，表示该插件已启用。

3、验证数据是否被缓存，再次请求上面的地址：

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

> 响应头 `Apisix-Cache-Status` 值变为了 HIT，说明数据已经被缓存

示例3：指定 cache_zone 为 `invalid_disk_cache` 与 `conf/config.yaml` 文件中指定的缓存区域 `disk_cache_one` 不一致。

```shell
$ curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "plugins": {
        "proxy-cache": {
            "cache_zone": "invalid_disk_cache",
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

```json
{"error_msg":"failed to check the configuration of plugin proxy-cache err: cache_zone invalid_disk_cache not found"}
```

响应错误信息，表示插件配置无效。

#### 清除缓存数据

如何清理缓存的数据，只需要指定请求的 method 为 PURGE。

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

> 响应码为200即表示删除成功，如果缓存的数据未找到将返回404。

再次请求，缓存数据未找到返回404：

```shell
$ curl -i http://127.0.0.1:9080/hello -X PURGE
HTTP/1.1 404 Not Found
Date: Wed, 18 Nov 2020 05:46:34 GMT
Content-Type: text/plain
Transfer-Encoding: chunked
Connection: keep-alive
Server: APISIX web server

<html>
<head><title>404 Not Found</title></head>
<body>
<center><h1>404 Not Found</h1></center>
<hr><center>openresty</center>
</body>
</html>
```

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
