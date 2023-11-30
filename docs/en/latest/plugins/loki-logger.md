---
title: loki-logger
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - Loki-logger
  - Grafana Loki
description: This document contains information about the Apache APISIX loki-logger Plugin.
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

The `loki-logger` plugin is used to forward logs to [Grafana Loki](https://grafana.com/oss/loki/) for analysis and storage.

When the Plugin is enabled, APISIX will serialize the request context information to [Log entries in JSON](https://grafana.com/docs/loki/latest/api/#push-log-entries-to-loki) and submit it to the batch queue. When the maximum batch size is exceeded, the data in the queue is pushed to Grafana Loki. See [batch processor](../batch-processor.md) for more details.

## Attributes

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| endpoint_addrs | array[string] | True |  | Loki API base URL, format like http://127.0.0.1:3100, supports HTTPS and domain names. If multiple endpoints are configured, they will be written randomly. |
| endpoint_uri | string | False | /loki/api/v1/push | If you are using a log collection service that is compatible with the Loki Push API, you can use this configuration item to customize the API path. |
| tenant_id | string | False | fake | Loki tenant ID. According to Loki's [multi-tenancy documentation](https://grafana.com/docs/loki/latest/operations/multi-tenancy/#multi-tenancy), its default value is set to the default value `fake` under single-tenancy. |
| log_labels | object | False | {job = "apisix"} | Loki log label. [APISIX variables](../apisix-variable.md) and [Nginx variables](http://nginx.org/en/docs/varindex.html) can be used by prefixing the string with `$`, both individual and combined, such as `$host` or `$remote_addr:$remote_port`. |
| ssl_verify        | boolean       | False    | true | When set to `true`, verifies the SSL certificate. |
| timeout           | integer       | False    | 3000ms | Timeout for the Loki service HTTP call. Range from 1 to 60,000ms.  |
| keepalive         | boolean       | False    | true | When set to `true`, keeps the connection alive for multiple requests. |
| keepalive_timeout | integer       | False    | 60000ms | Idle time after which the connection is closed. Range greater than or equal than 1000ms.  |
| keepalive_pool    | integer       | False    | 5       | Connection pool limit. Range greater than or equal than 1. |
| log_format | object | False    |          | Log format declared as key value pairs in JSON format. Values only support strings. [APISIX variables](../apisix-variable.md) and [Nginx variables](http://nginx.org/en/docs/varindex.html) can be used by prefixing the string with `$`. |
| include_req_body       | boolean | False    | false | When set to `true` includes the request body in the log. If the request body is too big to be kept in the memory, it can't be logged due to Nginx's limitations. |
| include_req_body_expr  | array   | False    |  | Filter for when the `include_req_body` attribute is set to `true`. Request body is only logged when the expression set here evaluates to `true`. See [lua-resty-expr](https://github.com/api7/lua-resty-expr) for more. |
| include_resp_body      | boolean | False    | false | When set to `true` includes the response body in the log. |
| include_resp_body_expr | array   | False    |  | Filter for when the `include_resp_body` attribute is set to `true`. Response body is only logged when the expression set here evaluates to `true`. See [lua-resty-expr](https://github.com/api7/lua-resty-expr) for more. |

This plugin supports using batch processors to aggregate and process entries (logs/data) in a batch. This avoids the need for frequently submitting the data. The batch processor submits data every `5` seconds or when the data in the queue reaches `1000`. See [Batch Processor](../batch-processor.md#configuration) for more information or setting your custom configuration.

## Metadata

You can also set the format of the logs by configuring the Plugin metadata. The following configurations are available:

| Name | Type | Required | Default | Description |
|------|------|----------|---------|-------------|
| log_format | object | False | {"host": "$host", "@timestamp": "$time_iso8601", "client_ip": "$remote_addr"} | Log format declared as key value pairs in JSON format. Values only support strings. [APISIX variables](../apisix-variable.md) and [Nginx variables](http://nginx.org/en/docs/varindex.html) can be used by prefixing the string with `$`. |

:::info IMPORTANT

Configuring the plugin metadata is global in scope. This means that it will take effect on all Routes and Services which use the `loki-logger` plugin.

:::

The example below shows how you can configure through the Admin API:

```shell
curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/loki-logger -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

## Enable plugin

The example below shows how you can enable the `loki-logger` plugin on a specific Route:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "plugins": {
        "loki-logger": {
            "endpoint_addrs" : ["http://127.0.0.1:3100"]
        }
    },
    "upstream": {
       "nodes": {
           "127.0.0.1:1980": 1
       },
       "type": "roundrobin"
    },
    "uri": "/hello"
}'
```

## Example usage

Now, if you make a request to APISIX, it will be logged in your Loki server:

```shell
curl -i http://127.0.0.1:9080/hello
```

## Delete the plugin

When you need to remove the `loki-logger` plugin, you can delete the corresponding JSON configuration with the following command and APISIX will automatically reload the relevant configuration without restarting the service:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["GET"],
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

## FAQ

### Logs are not pushed properly

Look at `error.log` for such a log.

```text
2023/04/30 13:45:46 [error] 19381#19381: *1075673 [lua] batch-processor.lua:95: Batch Processor[loki logger] failed to process entries: loki server returned status: 401, body: no org id, context: ngx.timer, client: 127.0.0.1, server: 0.0.0.0:9081
```

The error can be diagnosed based on the error code in the `failed to process entries: loki server returned status: 401, body: no org id` and the response body of the loki server.

### Getting errors when RPS is high?

- Make sure to `keepalive` related configuration is set properly. See [Attributes](#attributes) for more information.
- Check the logs in `error.log`, look for such a log.

    ```text
    2023/04/30 13:49:34 [error] 19381#19381: *1082680 [lua] batch-processor.lua:95: Batch Processor[loki logger] failed to process entries: loki server returned status: 429, body: Ingestion rate limit exceeded for user tenant_1 (limit: 4194304 bytes/sec) while attempting to ingest '1000' lines totaling '616307' bytes, reduce log volume or contact your Loki administrator to see if the limit can be increased, context: ngx.timer, client: 127.0.0.1, server: 0.0.0.0:9081
    ```

  - The logs usually associated with high QPS look like the above. The error is: `Ingestion rate limit exceeded for user tenant_1 (limit: 4194304 bytes/sec) while attempting to ingest '1000' lines totaling '616307' bytes, reduce log volume or contact your Loki administrator to see if the limit can be increased`.
  - Refer to [Loki documentation](https://grafana.com/docs/loki/latest/configuration/#limits_config) to add limits on the amount of default and burst logs, such as `ingestion_rate_mb` and `ingestion_burst_size_mb`.

    As the test during development, setting the `ingestion_burst_size_mb` to 100 allows APISIX to push the logs correctly at least at 10000 RPS.
