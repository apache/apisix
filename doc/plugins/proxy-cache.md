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

- [中文](../zh-cn/plugins/proxy-cache.md)

# proxy-cache

The proxy-cache plugin, which provides the ability to cache upstream response data and can be used with other plugins. The plugin supports disk-based caching and will support the memory-based caching in the future. The data that needs to be cached can be determined by the response code or request method and more complex caching policies can be configured by no_cache and cache_bypass attributes.

*Note*:
1. The cache expiration time cannot be configured dynamically. The expiration time can only be set by the upstream response header `Expires` or `Cache-Control`, and the default cache expiration time is 10s if there is no `Expires` or `Cache-Control` in the upstream response header
2. If the upstream service is not available and APISIX will return 502 or 504, then 502 or 504 will be cached for 10s.

## Attributes

| Name               | Type           | Requirement | Default                   | Valid                                                                           | Description                                                                                                                                                                                                                                  |
| ------------------ | -------------- | ----------- | ------------------------- | ------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| cache_zone         | string         | optional    |  disk_cache_one           |                                                                                 | Specify which cache area to use, each cache area can be configured with different paths. In addition, cache areas can be predefined in conf/config.yaml file. When the default value is not used, the specified cache area is inconsistent with the pre-defined cache area in the conf/config.yaml file, and the cache is invalid.  |
| cache_key          | array[string]  | optional    | ["$host", "$request_uri"] |                                                                                 | key of a cache, can use variables. For example: ["$host", "$uri", "-cache-id"]                                                                                                                                                               |
| cache_bypass       | array[string]  | optional    |                           |                                                                                 | Whether to skip cache retrieval. That is, do not look for data in the cache. It can use variables, and note that cache data retrieval will be skipped when the value of this attribute is not empty or not '0'. For example: ["$arg_bypass"] |
| cache_method       | array[string]  | optional    | ["GET", "HEAD"]           | ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD","OPTIONS", "CONNECT", "TRACE"] | Decide whether to be cached according to the request method                                                                                                                                                                                  |
| cache_http_status  | array[integer] | optional    | [200, 301, 404]           | [200, 599]                                                                      | Decide whether to be cached according to the upstream response status                                                                                                                                                                        |
| hide_cache_headers | boolean        | optional    | false                     |                                                                                 | Whether to return the Expires and Cache-Control response headers to the client,                                                                                                                                                              |
| no_cache           | array[string]  | optional    |                           |                                                                                 | Whether to cache data, it can use variables, and note that the data will not be cached when the value of this attribute is not empty or not '0'.                                                                                             |

Note:
1. The variable starts with $.
2. The attribute can use a combination of the variable and the string, but it needs to be written separately as an array, and the final values are stitched together after the variable is parsed.

Example configuration in the `conf/config.yaml` file:

```yaml
proxy_cache:                       # Proxy Caching configuration
    cache_ttl: 10s                 # The default caching time if the upstream does not specify the cache time
    zones:                         # The parameters of a cache
    - name: disk_cache_one         # The name of the cache, administrator can be specify
                                   # which cache to use by name in the admin api
      memory_size: 50m             # The size of shared memory, it's used to store the cache index
      disk_size: 1G                # The size of disk, it's used to store the cache data
      disk_path: "/tmp/disk_cache_one" # The path to store the cache data
      cache_levels: "1:2"          # The hierarchy levels of a cache
```

### Examples

#### Enable the plugin

Example 1: The cache_zone parameter defaults to `disk_cache_one`

1:  enable the proxy-cache plugin for a specific route :

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

> http status is '200' and the response header contains 'Apisix-Cache-Status' to indicate that the plugin is enabled.

2: Verify that the data is cached, request the address above again:

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

Example 2: Customize the cache_zone parameter to `disk_cache_two`

1. Specify the cache area and other information in the `conf/config.yaml` file:

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

2. Enable the `proxy-cache` plugin for a specific route:

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

3. Verify that the data is cached and request the above address again:

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

> The response header `Apisix-Cache-Status` value has changed to HIT, indicating that the data has been cached

Example 3: Specifying cache_zone as `invalid_disk_cache` is inconsistent with the cache area `disk_cache_one` specified in the `conf/config.yaml` file.

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

In response to an error message, the plug-in configuration is invalid.

#### Clear cached data

How to clean the cached data only needs to specify the requested method as PURGE.

Test Plugin:

```shell
$ curl -i http://127.0.0.1:9080/hello -X PURGE
HTTP/1.1 200 OK
Date: Tue, 03 Mar 2020 11:17:35 GMT
Content-Type: text/plain
Transfer-Encoding: chunked
Connection: keep-alive
Server: APISIX web server
```

> If the response code is 200, it means the deletion is successful. If the cached data is not found, 404 will be returned.

Request again, the cached data is not found and return 404:

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
