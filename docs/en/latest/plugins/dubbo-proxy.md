---
title: dubbo-proxy
keywords:
  - Apache APISIX
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

If you are using OpenResty, you need to build it with Dubbo support. See [How do I build the APISIX runtime environment](./../FAQ.md#how-do-i-build-the-apisix-runtime-environment) for details.

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

## Enable Plugin

To enable the `dubbo-proxy` Plugin, you have to add it in your configuration file (`conf/config.yaml`):

```yaml title="conf/config.yaml"
plugins:
  - ...
  - dubbo-proxy
```

Now, when APISIX is reloaded, you can add it to a specific Route as shown below:

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/upstreams/1  -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "nodes": {
        "127.0.0.1:20880": 1
    },
    "type": "roundrobin"
}'

curl http://127.0.0.1:9180/apisix/admin/routes/1  -H "X-API-KEY: $admin_key" -X PUT -d '
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

APISIX dubbo plugin uses `hessian2` as the serialization protocol. It supports only `Map<String, Object>` as the request and response data type.

### Application

Your dubbo config should be configured to use `hessian2` as the serialization protocol.

```yml
dubbo:
  ...
  protocol:
    ...
    serialization: hessian2
```

Your application should implement the interface with the request and response data type as `Map<String, Object>`.

```java
public interface DemoService {
    Map<String, Object> sayHello(Map<String, Object> context);
}
```

### Request and Response

If you need to pass request data, you can add the data to the HTTP request header. The plugin will convert the HTTP request header to the request data of the Dubbo service. Here is a sample HTTP request that passes `user` information:

```bash
curl -i -X POST 'http://localhost:9080/hello' \
                    --header 'user: apisix'


HTTP/1.1 200 OK
Date: Mon, 15 Jan 2024 10:15:57 GMT
Content-Type: text/plain; charset=utf-8
...
hello: apisix
...
Server: APISIX/3.8.0
```

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

## Delete Plugin

To remove the `dubbo-proxy` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  -H "X-API-KEY: $admin_key" -X PUT -d '
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
