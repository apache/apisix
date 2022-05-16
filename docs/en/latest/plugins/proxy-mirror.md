---
title: proxy-mirror
keywords:
  - APISIX
  - Plugin
  - Proxy Mirror
  - proxy-mirror
description: This document contains information about the Apache APISIX proxy-mirror Plugin.
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

The `proxy-mirror` Plugin can be used to mirror client requests.

:::note

The response returned by the mirror request is ignored.

:::

## Attributes

| Name         | Type   | Required | Default | Valid values | Description                                                                                                               |
|--------------|--------|----------|---------|--------------|---------------------------------------------------------------------------------------------------------------------------|
| host         | string | True     |         |              | Address of the mirror service. It needs to contain the scheme but without the path. For example, `http://127.0.0.1:9797`. |
| path         | string | False    |         |              | Path of the mirror request. If unspecified, current path will be used.                                                    |
| sample_ratio | number | False    | 1       | [0.00001, 1] | Ratio of the requests that will be mirrored.                                                                              |

You can customize the proxy timeouts for the mirrored sub-requests by configuring the `plugin_attr` key in your configuration file (`conf/config.yaml`). This can be used for mirroring traffic to a slow backend.

```yaml title="conf/config.yaml"
plugin_attr:
  proxy-mirror:
    timeout:
      connect: 2000ms
      read: 2000ms
      send: 2000ms
```

| Name    | Type   | Default | Description                               |
|---------|--------|---------|-------------------------------------------|
| connect | string | 60s     | Connect timeout to the mirrored Upstream. |
| read    | string | 60s     | Read timeout to the mirrored Upstream.    |
| send    | string | 60s     | Send timeout to the mirrored Upstream.    |

## Enabling the Plugin

You can enable the Plugin on a specific Route as shown below:

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "plugins": {
        "proxy-mirror": {
           "host": "http://127.0.0.1:9797"
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

## Example usage

Once you have configured the Plugin as shown above, the requests made will be mirrored to the configured host.

```shell
curl http://127.0.0.1:9080/hello -i
```

```shell
HTTP/1.1 200 OK
Content-Type: application/octet-stream
Content-Length: 12
Connection: keep-alive
Server: APISIX web server
Date: Wed, 18 Mar 2020 13:01:11 GMT
Last-Modified: Thu, 20 Feb 2020 14:21:41 GMT

hello world
```

:::tip

For testing you can create a test server by running:

```shell
python -m http.server 9797
```

:::

## Disable Plugin

To disable the `proxy-mirror` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

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
