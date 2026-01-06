---
title: tencent-cloud-cls
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - CLS
  - Tencent Cloud
description: This document contains information about the Apache APISIX tencent-cloud-cls Plugin.
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

The `tencent-cloud-cls` Plugin uses [TencentCloud CLS](https://cloud.tencent.com/document/product/614) API to forward APISIX logs to your topic.

## Attributes

| Name              | Type    | Required | Default | Valid values  | Description                                                                                                                                                      |
| ----------------- | ------- |----------|---------|---------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| cls_host          | string  | Yes      |         |               | CLS API host，please refer [Uploading Structured Logs](https://www.tencentcloud.com/document/api/614/16873).                                                      |
| cls_topic         | string  | Yes      |         |               | topic id of CLS.                                                                                                                                                 |
| secret_id         | string  | Yes      |         |               | SecretId of your API key.                                                                                                                                        |
| secret_key        | string  | Yes      |         |               | SecretKey of your API key.                                                                                                                                       |
| sample_ratio      | number  | No       | 1       | [0.00001, 1]  | How often to sample the requests. Setting to `1` will sample all requests.                                                                                       |
| include_req_body  | boolean | No       | false   | [false, true] | When set to `true` includes the request body in the log. If the request body is too big to be kept in the memory, it can't be logged due to NGINX's limitations. |
| include_req_body_expr  | array   | No       |         |               | Filter for when the `include_req_body` attribute is set to `true`. Request body is only logged when the expression set here evaluates to `true`. See [lua-resty-expr](https://github.com/api7/lua-resty-expr) for more.                                                                                                                          |
| include_resp_body | boolean | No       | false   | [false, true] | When set to `true` includes the response body in the log.                                                                                                        |
| include_resp_body_expr | array   | No  |         |               | Filter for when the `include_resp_body` attribute is set to `true`. Response body is only logged when the expression set here evaluates to `true`. See [lua-resty-expr](https://github.com/api7/lua-resty-expr) for more.                                                                                                                        |
| global_tag        | object  | No       |         |               | kv pairs in JSON，send with each log.                                                                                                                             |
| log_format       | object  | No       |         |               | Log format declared as key-value pairs in JSON. Values support strings and nested objects (up to five levels deep; deeper fields are truncated). Within strings, [APISIX](../apisix-variable.md) or [NGINX](http://nginx.org/en/docs/varindex.html) variables can be referenced by prefixing with `$`. |

NOTE: `encrypt_fields = {"secret_key"}` is also defined in the schema, which means that the field will be stored encrypted in etcd. See [encrypted storage fields](../plugin-develop.md#encrypted-storage-fields).

This Plugin supports using batch processors to aggregate and process entries (logs/data) in a batch. This avoids the need for frequently submitting the data. The batch processor submits data every `5` seconds or when the data in the queue reaches `1000`. See [Batch Processor](../batch-processor.md#configuration) for more information or setting your custom configuration.

### Example of default log format

```json
{
    "response": {
        "headers": {
            "content-type": "text/plain",
            "connection": "close",
            "server": "APISIX/3.7.0",
            "transfer-encoding": "chunked"
        },
        "size": 136,
        "status": 200
    },
    "route_id": "1",
    "upstream": "127.0.0.1:1982",
    "client_ip": "127.0.0.1",
    "apisix_latency": 100.99985313416,
    "service_id": "",
    "latency": 103.99985313416,
    "start_time": 1704525145772,
    "server": {
        "version": "3.7.0",
        "hostname": "localhost"
    },
    "upstream_latency": 3,
    "request": {
        "headers": {
            "connection": "close",
            "host": "localhost"
        },
        "url": "http://localhost:1984/opentracing",
        "querystring": {},
        "method": "GET",
        "size": 65,
        "uri": "/opentracing"
    }
}
```

## Metadata

You can also set the format of the logs by configuring the Plugin metadata. The following configurations are available:

| Name       | Type   | Required | Default                                                                       | Description                                                                                                                                                                                                                                             |
| ---------- | ------ | -------- | ----------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| log_format | object | False    |   | Log format declared as key-value pairs in JSON. Values support strings and nested objects (up to five levels deep; deeper fields are truncated). Within strings, [APISIX](../apisix-variable.md) or [NGINX](http://nginx.org/en/docs/varindex.html) variables can be referenced by prefixing with `$`. |
| max_pending_entries | integer | False | | Maximum number of pending entries that can be buffered in batch processor before it starts dropping them. |

:::info IMPORTANT

Configuring the Plugin metadata is global in scope. This means that it will take effect on all Routes and Services which use the `tencent-cloud-cls` Plugin.

:::

The example below shows how you can configure through the Admin API:

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/tencent-cloud-cls \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "log_format": {
        "host": "$host",
        "@timestamp": "$time_iso8601",
        "client_ip": "$remote_addr",
        "request": { "method": "$request_method", "uri": "$request_uri" },
        "response": { "status": "$status" }
    }
}'
```

With this configuration, your logs would be formatted as shown below:

```shell
{"host":"localhost","@timestamp":"2020-09-23T19:05:05-04:00","client_ip":"127.0.0.1","request":{"method":"GET","uri":"/hello"},"response":{"status":200},"route_id":"1"}
{"host":"localhost","@timestamp":"2020-09-23T19:05:05-04:00","client_ip":"127.0.0.1","request":{"method":"GET","uri":"/hello"},"response":{"status":200},"route_id":"1"}
```

## Enable Plugin

The example below shows how you can enable the Plugin on a specific Route:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "plugins": {
        "tencent-cloud-cls": {
            "cls_host": "ap-guangzhou.cls.tencentyun.com",
            "cls_topic": "${your CLS topic name}",
            "global_tag": {
                "module": "cls-logger",
                "server_name": "YourApiGateWay"
            },
            "include_req_body": true,
            "include_resp_body": true,
            "secret_id": "${your secret id}",
            "secret_key": "${your secret key}"
        }
    },
      "upstream": {
           "type": "roundrobin",
           "nodes": {
               "127.0.0.1:1980": 1
           }
      },
      "uri": "/hello"
}'
```

## Example usage

Now, if you make a request to APISIX, it will be logged in your cls topic:

```shell
curl -i http://127.0.0.1:9080/hello
```

## Delete Plugin

To disable this Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/hello",
    "plugins": {},
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```
