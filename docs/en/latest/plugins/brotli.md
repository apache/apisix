---
title: brotli
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - brotli
description: This document contains information about the Apache APISIX brotli Plugin.
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

## Description

The `brotli` Plugin dynamically sets the behavior of [brotli in Nginx](https://github.com/google/ngx_brotli).

## Prerequisites

This Plugin requires brotli shared libraries.

The example commands to build and install brotli shared libraries:

``` shell
wget https://github.com/google/brotli/archive/refs/tags/v1.1.0.zip
unzip v1.1.0.zip
cd brotli-1.1.0 && mkdir build && cd build
cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local/brotli ..
sudo cmake --build . --config Release --target install
sudo sh -c "echo /usr/local/brotli/lib >> /etc/ld.so.conf.d/brotli.conf"
sudo ldconfig
```

:::caution

If the upstream is returning a compressed response, then the Brotli plugin won't be able to compress it.

:::

## Attributes

| Name           | Type                 | Required | Default       | Valid values | Description                                                                             |
|----------------|----------------------|----------|---------------|--------------|-----------------------------------------------------------------------------------------|
| types          | array[string] or "*" | False    | ["text/html"] |              | Dynamically sets the `brotli_types` directive. Special value `"*"` matches any MIME type. |
| min_length     | integer              | False    | 20            | >= 1         | Dynamically sets the `brotli_min_length` directive. |
| comp_level     | integer              | False    | 6             | [0, 11]      | Dynamically sets the `brotli_comp_level` directive. |
| mode           | integer              | False    | 0             | [0, 2]       | Dynamically sets the `brotli decompress mode`, more info in [RFC 7932](https://tools.ietf.org/html/rfc7932). |
| lgwin          | integer              | False    | 19            | [0, 10-24]   | Dynamically sets the `brotli sliding window size`, `lgwin` is Base 2 logarithm of the sliding window size, set to `0` lets compressor decide over the optimal value, more info in [RFC 7932](https://tools.ietf.org/html/rfc7932). |
| lgblock        | integer              | False    | 0             | [0, 16-24]   | Dynamically sets the `brotli input block size`, `lgblock` is Base 2 logarithm of the maximum input block size, set to `0` lets compressor decide over the optimal value, more info in [RFC 7932](https://tools.ietf.org/html/rfc7932). |
| http_version   | number               | False    | 1.1           | 1.1, 1.0     | Like the `gzip_http_version` directive, sets the minimum HTTP version of a request required to compress a response. |
| vary           | boolean              | False    | false         |              | Like the `gzip_vary` directive, enables or disables inserting the “Vary: Accept-Encoding” response header field. |

## Enable Plugin

The example below enables the `brotli` Plugin on the specified Route:

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl -i http://127.0.0.1:9180/apisix/admin/routes/1  -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/",
    "plugins": {
        "brotli": {
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "httpbin.org": 1
        }
    }
}'
```

## Example usage

Once you have configured the Plugin as shown above, you can make a request as shown below:

```shell
curl http://127.0.0.1:9080/ -i -H "Accept-Encoding: br"
```

```
HTTP/1.1 200 OK
Content-Type: text/html; charset=utf-8
Transfer-Encoding: chunked
Connection: keep-alive
Date: Tue, 05 Dec 2023 03:06:49 GMT
Access-Control-Allow-Origin: *
Access-Control-Allow-Credentials: true
Server: APISIX/3.6.0
Content-Encoding: br

Warning: Binary output can mess up your terminal. Use "--output -" to tell
Warning: curl to output it to your terminal anyway, or consider "--output
Warning: <FILE>" to save to a file.
```

## Delete Plugin

To remove the `brotli` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "httpbin.org": 1
        }
    }
}'
```
