---
title: Zstandard Compression (zstd)
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - zstd
description: This document contains information about the Apache APISIX zstd Plugin.
---

<!--
#
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.
#
-->

## Description

The `zstd` Plugin compresses HTTP responses with [Zstandard](https://facebook.github.io/zstd/) (`Content-Encoding: zstd`) when the client sends `Accept-Encoding: zstd`. It works like the [brotli](./brotli.md) Plugin, but for clients that support the zstd content coding defined by [RFC 9659](https://datatracker.ietf.org/doc/html/rfc9659), such as recent Chrome and Firefox versions.

## Prerequisites

This Plugin requires the `libzstd` shared library, which is preinstalled on most systems. If missing, install it with:

``` shell
sudo apt-get install libzstd1
```

or on macOS:

``` shell
brew install zstd
```

:::caution

If the upstream is returning a compressed response, then the `zstd` Plugin won't be able to compress it.

:::

## Attributes

| Name           | Type                 | Required | Default       | Valid values | Description                                                                             |
|----------------|----------------------|----------|---------------|--------------|-----------------------------------------------------------------------------------------|
| types          | array[string] or "*" | False    | ["text/html"] |              | Sets the MIME types to compress. Special value `"*"` matches any MIME type. |
| min_length     | integer              | False    | 20            | >= 1         | Sets the minimum response length, in bytes, required to compress a response. |
| comp_level     | integer              | False    | 3             | [1, 19]      | Sets the zstd compression level. Levels above 19 are not allowed, as they enlarge the decoder window beyond the 8 MB that [RFC 9659](https://datatracker.ietf.org/doc/html/rfc9659) requires HTTP decoders to support. |
| http_version   | number               | False    | 1.1           | 1.1, 1.0     | Like the `gzip_http_version` directive, sets the minimum HTTP version of a request required to compress a response. |
| vary           | boolean              | False    | false         |              | Like the `gzip_vary` directive, enables or disables inserting the "Vary: Accept-Encoding" response header field. |

## Enable Plugin

The example below enables the `zstd` Plugin on the specified Route:

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
        "zstd": {
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

Once configured, responses are compressed when the client advertises support:

```shell
curl -i -H "Accept-Encoding: zstd" http://127.0.0.1:9080/ --output compressed.zst
```

```
HTTP/1.1 200 OK
Content-Encoding: zstd
```

Requests without `Accept-Encoding: zstd` receive the uncompressed response.

## Delete Plugin

To remove the `zstd` Plugin, you can delete the corresponding JSON configuration from the Route configuration. APISIX will automatically reload and complete the deletion.

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
