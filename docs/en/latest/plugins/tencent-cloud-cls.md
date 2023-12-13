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
| ----------------- | ------- | -------- |---------| ------------- |------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| cls_host          | string  | Yes      |         |               | CLS API host，please refer [Uploading Structured Logs](https://www.tencentcloud.com/document/api/614/16873).                                                      |
| cls_topic         | string  | Yes      |         |               | topic id of CLS.                                                                                                                                                 |
| secret_id         | string  | Yes      |         |               | SecretId of your API key.                                                                                                                                        |
| secret_key        | string  | Yes      |         |               | SecretKey of your API key.                                                                                                                                       |
| sample_ratio      | number  | No       | 1       | [0.00001, 1]  | How often to sample the requests. Setting to `1` will sample all requests.                                                                                       |
| include_req_body  | boolean | No       | false   | [false, true] | When set to `true` includes the request body in the log. If the request body is too big to be kept in the memory, it can't be logged due to NGINX's limitations. |
| include_resp_body | boolean | No       | false   | [false, true] | When set to `true` includes the response body in the log.                                                                                                        |
| global_tag        | object  | No       |         |               | kv pairs in JSON，send with each log.                                                                                                                             |
| log_format       | object  | No    |  |              | Log format declared as key value pairs in JSON format. Values only support strings. [APISIX](../apisix-variable.md) or [Nginx](http://nginx.org/en/docs/varindex.html) variables can be used by prefixing the string with `$`. |

NOTE: `encrypt_fields = {"secret_key"}` is also defined in the schema, which means that the field will be stored encrypted in etcd. See [encrypted storage fields](../plugin-develop.md#encrypted-storage-fields).

This Plugin supports using batch processors to aggregate and process entries (logs/data) in a batch. This avoids the need for frequently submitting the data. The batch processor submits data every `5` seconds or when the data in the queue reaches `1000`. See [Batch Processor](../batch-processor.md#configuration) for more information or setting your custom configuration.

## Metadata

You can also set the format of the logs by configuring the Plugin metadata. The following configurations are available:

| Name       | Type   | Required | Default                                                                       | Description                                                                                                                                                                                                                                             |
| ---------- | ------ | -------- | ----------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| log_format | object | False    |   | Log format declared as key value pairs in JSON format. Values only support strings. [APISIX](../apisix-variable.md) or [Nginx](http://nginx.org/en/docs/varindex.html) variables can be used by prefixing the string with `$`. |

:::info IMPORTANT

Configuring the Plugin metadata is global in scope. This means that it will take effect on all Routes and Services which use the `tencent-cloud-cls` Plugin.

:::

The example below shows how you can configure through the Admin API:

```shell
curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/tencent-cloud-cls \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "log_format": {
        "host": "$host",
        "@timestamp": "$time_iso8601",
        "client_ip": "$remote_addr"
    }
}'
```

With this configuration, your logs would be formatted as shown below:

```shell
{"host":"localhost","@timestamp":"2020-09-23T19:05:05-04:00","client_ip":"127.0.0.1","route_id":"1"}
{"host":"localhost","@timestamp":"2020-09-23T19:05:05-04:00","client_ip":"127.0.0.1","route_id":"1"}
```

## Enable Plugin

The example below shows how you can enable the Plugin on a specific Route:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
