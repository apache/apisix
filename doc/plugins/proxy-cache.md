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

- [中文](/doc/zh-cn/plugins/proxy-cache.md)

# proxy-cache

The proxy-cache plugin, which provides the ability to cache upstream response data and can be used with other plugins. The plugin supports disk-based caching and will support the memory-based caching in the future. The data that needs to be cached can be determined by the response code or request method and more complex caching policies can be configured by no_cache and cache_bypass attributes.

*Note*:
1. The cache expiration time cannot be configured dynamically. The expiration time can only be set by the upstream response header `Expires` or `Cache-Control`, and the default cache expiration time is 10s if there is no `Expires` or `Cache-Control` in the upstream response header
2. If the upstream service is not available and APISIX will return 502 or 504, then 502 or 504 will be cached for 10s.

## Attributes

| Name               | Type           | Requirement | Default                   | Valid                                                                           | Description                                                                                                                                                                                                                                  |
| ------------------ | -------------- | ----------- | ------------------------- | ------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| cache_zone         | string         | required    |                           |                                                                                 | Specify which cache area to use, each cache area can be configured with different paths. In addition, cache areas can be predefined in conf/config.yaml file                                                                                 |
| cache_key          | array[string]  | optional    | ["$host", "$request_uri"] |                                                                                 | key of a cache, can use variables. For example: ["$host", "$uri", "-cache-id"]                                                                                                                                                               |
| cache_bypass       | array[string]  | optional    |                           |                                                                                 | Whether to skip cache retrieval. That is, do not look for data in the cache. It can use variables, and note that cache data retrieval will be skipped when the value of this attribute is not empty or not '0'. For example: ["$arg_bypass"] |
| cache_method       | array[string]  | optional    | ["GET", "HEAD"]           | ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD","OPTIONS", "CONNECT", "TRACE"] | Decide whether to be cached according to the request method                                                                                                                                                                                  |
| cache_http_status  | array[integer] | optional    | [200, 301, 404]           | [200, 599]                                                                      | Decide whether to be cached according to the upstream response status                                                                                                                                                                        |
| hide_cache_headers | boolean        | optional    | false                     |                                                                                 | Whether to return the Expires and Cache-Control response headers to the client,                                                                                                                                                              |
| no_cache           | array[string]  | optional    |                           |                                                                                 | Whether to cache data, it can use variables, and note that the data will not be cached when the value of this attribute is not empty or not '0'.                                                                                             |

Note:
1. The variable starts with $.
2. The attribute can use a combination of the variable and the string, but it needs to be written separately as an array, and the final values are stitched together after the variable is parsed.

### Examples

#### Enable the plugin

1:  enable the proxy-cache plugin for a specific route :

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

Test Plugin:

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
> http status is '200' and the response header contains 'Apisix-Cache-Status' to indicate that the plug-in is enabled.

2: Verify that the file is cached, request the address above again:


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

> Response header  Apisix-Cache-Status has changed to HIT, indicating that the file has been cached.

3: How to clean up the cached file, simply specify the request method as PURGE:


```shell
$ curl -i http://127.0.0.1:9080/hello -X PURGE
HTTP/1.1 200 OK
Date: Tue, 03 Mar 2020 11:17:35 GMT
Content-Type: text/plain
Transfer-Encoding: chunked
Connection: keep-alive
Server: APISIX web server
```

> The response status is 200, indicating that the file was deleted successfully. And return 404 if the file is not found.

## Disable Plugin

Remove the corresponding JSON in the plugin configuration to disable the plugin immediately without restarting the service:


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

The plugin has been disabled now.
