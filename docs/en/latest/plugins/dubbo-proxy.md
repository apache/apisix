---
title: dubbo-proxy
keywords:
  - APISIX
  - API Gateway
  - Plugin
  - Apache Dubbo
  - dubbo-proxy
description: This document contains information about the Apache APISIX dubbo-proxy Plugin.
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

The `dubbo-proxy` Plugin allows you to proxy HTTP requests to [Apache Dubbo](https://dubbo.apache.org/en/index.html).

:::info IMPORTANT

If you are using OpenResty, you need to build it with Dubbo support. See [How do I build the APISIX base environment](./../FAQ.md#how-do-i-build-the-apisix-base-environment) for details.

:::

## Runtime Attributes

| Name            | Type   | Required | Default              | Description                     |
| --------------- | ------ | -------- | -------------------- | ------------------------------- |
| service_name    | string | True     |                      | Dubbo provider service name.    |
| service_version | string | True     |                      | Dubbo provider service version. |
| method          | string | False    | The path of the URI. | Dubbo provider service method.  |

## Static Attributes

| Name                     | Type   | Required | Default | Valid values | Description                                                     |
| ------------------------ | ------ | -------- | ------- | ------------ | --------------------------------------------------------------- |
| upstream_multiplex_count | number | True | 32      | >= 1         | Maximum number of multiplex requests in an upstream connection. |

## Enabling the Plugin

To enable the `dubbo-proxy` Plugin, you have to add it in your configuration file (`conf/config.yaml`):

```yaml title="conf/config.yaml"
plugins:
  - ...
  - dubbo-proxy
```

Now, when APISIX is reloaded, you can add it to a specific Route as shown below:

```shell
curl http://127.0.0.1:9180/apisix/admin/upstreams/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "nodes": {
        "127.0.0.1:20880": 1
    },
    "type": "roundrobin"
}'

curl http://127.0.0.1:9180/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uris": [
        "/hello"
    ],
    "plugins": {
        "dubbo-proxy": {
            "service_name": "org.apache.dubbo.sample.tengine.DemoService",
            "service_version": "0.0.0",
            "method": "tengineDubbo"
        }
    },
    "upstream_id": 1
}'
```

## Example usage

You can follow the [Quick Start](https://github.com/alibaba/tengine/tree/master/modules/mod_dubbo#quick-start) guide in Tengine with the configuration above for testing.

Dubbo returns data in the form `Map<String, String>`.

If the returned data is:

```json
{
  "status": "200",
  "header1": "value1",
  "header2": "value2",
  "body": "body of the message"
}
```

The converted HTTP response will be:

```
HTTP/1.1 200 OK
...
header1: value1
header2: value2
...

body of the message
```

## Disable Plugin

To disable the `dubbo-proxy` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["GET"],
    "uris": [
        "/hello"
    ],
    "plugins": {
    },
    "upstream_id": 1
    }
}'
```

To completely disable the `dubbo-proxy` Plugin, you can remove it from your configuration file (`conf/config.yaml`):

```yaml title="conf/config.yaml"
plugins:
  # - dubbo-proxy
```
