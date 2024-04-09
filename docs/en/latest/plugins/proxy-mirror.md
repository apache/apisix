---
title: proxy-mirror
keywords:
  - Apache APISIX
  - API Gateway
  - Proxy Mirror
description: This document describes the information about the Apache APISIX proxy-mirror Plugin, you can use it to mirror the client requests.
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

The `proxy-mirror` Plugin can be used to mirror client requests. Traffic mirroring duplicates the real online traffic to the mirroring service. This enables specific analysis of the online traffic or request content without interrupting the online service.

:::note

The response returned by the mirror request is ignored.

:::

## Attributes

| Name         | Type   | Required | Default | Valid values | Description                                                                                                               |
|--------------|--------|----------|---------|--------------|---------------------------------------------------------------------------------------------------------------------------|
| host         | string | True     |         |              | Address of the mirror service. It needs to contain the scheme (`http(s)` or `grpc(s)`) but without the path. For example, `http://127.0.0.1:9797`. |
| path         | string | False    |         |              | Path of the mirror request. If unspecified, current path will be used. If it is for mirroring grpc traffic, this option is no longer applicable.                                                   |
| path_concat_mode | string | False   |   replace     | ["replace", "prefix"]       | If the path of a mirror request is specified, set the concatenation mode of request paths. The `replace` mode will directly use `path` as the path of the mirror request. The `prefix` mode will use the `path` + `source request URI` as the path to the mirror request. If it is for mirroring grpc traffic, this option is no longer applicable too. |
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

## Enable Plugin

You can enable the Plugin on a specific Route as shown below:

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  \
  -H "X-API-KEY: $admin_key" -X PUT -d '
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

### Specify the timeout for mirror subrequests

We can specify the `timeout` for subrequests in `plugin_attr` in `conf/config.yaml`. This is useful in connection reuse scenarios when mirroring traffic to a very slow backend service.

Since mirror requests are implemented as sub-requests, delays in sub-requests will block the original request until the sub-requests are completed. So you can configure the timeout time to protect the sub-requests from excessive delays that affect the original requests.

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| connect | string | 60s | Connection timeout for mirror request to upstream. |
| read | string | 60s | The time that APISIX maintains the connection with the mirror server; if APISIX does not receive a response from the mirror server within this time, the connection is closed. |
| send | string | 60s | The time that APISIX maintains the connection with the mirror server; if APISIX does not send a request within this time, the connection is closed. |

```yaml
plugin_attr:
  proxy-mirror:
    timeout:
      connect: 2000ms
      read: 2000ms
      send: 2000ms
```

## Example usage

:::tip

For testing you can create a test server by running:

```shell
python -m http.server 9797
```

:::

Once you have configured the Plugin as shown above, the requests made will be mirrored to the configured host.

```shell
curl http://127.0.0.1:9080/hello -i
```

```shell
HTTP/1.1 200 OK
...
hello world
```

## Delete Plugin

To remove the `proxy-mirror` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
  -H "X-API-KEY: $admin_key" -X PUT -d '
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
