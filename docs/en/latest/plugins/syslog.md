---
title: syslog
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - Syslog
description: This document contains information about the Apache APISIX syslog Plugin.
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

The `syslog` Plugin is used to push logs to a Syslog server.

Logs can be set as JSON objects.

## Attributes

| Name             | Type    | Required | Default      | Valid values  | Description                                                                                                              |
|------------------|---------|----------|--------------|---------------|--------------------------------------------------------------------------------------------------------------------------|
| host             | string  | True     |              |               | IP address or the hostname of the Syslog server.                                                                         |
| port             | integer | True     |              |               | Target port of the Syslog server.                                                                                        |
| name             | string  | False    | "sys logger" |               | Identifier for the server. If you use Prometheus to monitor APISIX metrics, the name is exported in `apisix_batch_process_entries`.                                                                                               |
| timeout          | integer | False    | 3000         | [1, ...]      | Timeout in ms for the upstream to send data.                                                                             |
| tls              | boolean | False    | false        |               | When set to `true` performs TLS verification.                                                                            |
| flush_limit      | integer | False    | 4096         | [1, ...]      | Maximum size of the buffer (KB) and the current message before it is flushed and written to the server.                  |
| drop_limit       | integer | False    | 1048576      |               | Maximum size of the buffer (KB) and the current message before the current message is dropped because of the size limit. |
| sock_type        | string  | False    | "tcp"        | ["tcp", "udp] | Transport layer protocol to use.                                                                                         |
| pool_size        | integer | False    | 5            | [5, ...]      | Keep-alive pool size used by `sock:keepalive`.                                                                           |
| log_format       | object  | False    |  |              | Log format declared as key-value pairs in JSON. Values support strings and nested objects (up to five levels deep; deeper fields are truncated). Within strings, [APISIX](../apisix-variable.md) or [NGINX](http://nginx.org/en/docs/varindex.html) variables can be referenced by prefixing with `$`. |
| include_req_body | boolean | False    | false        | [false, true] | When set to `true` includes the request body in the log.                                                                 |
| include_req_body_expr  | array         | False    |         |               | Filter for when the `include_req_body` attribute is set to `true`. Request body is only logged when the expression set here evaluates to `true`. See [lua-resty-expr](https://github.com/api7/lua-resty-expr) for more.        |
| include_resp_body      | boolean       | False    | false   | [false, true] | When set to `true` includes the response body in the log.                                                                                                                                                                      |
| include_resp_body_expr | array         | False    |         |               | When the `include_resp_body` attribute is set to `true`, use this to filter based on [lua-resty-expr](https://github.com/api7/lua-resty-expr). If present, only logs the response if the expression evaluates to `true`.       |

This Plugin supports using batch processors to aggregate and process entries (logs/data) in a batch. This avoids the need for frequently submitting the data. The batch processor submits data every `5` seconds or when the data in the queue reaches `1000`. See [Batch Processor](../batch-processor.md#configuration) for more information or setting your custom configuration.

### meta_format example

```text
"<46>1 2024-01-06T02:30:59.145Z 127.0.0.1 apisix 82324 - - {\"response\":{\"status\":200,\"size\":141,\"headers\":{\"content-type\":\"text/plain\",\"server\":\"APISIX/3.7.0\",\"transfer-encoding\":\"chunked\",\"connection\":\"close\"}},\"route_id\":\"1\",\"server\":{\"hostname\":\"baiyundeMacBook-Pro.local\",\"version\":\"3.7.0\"},\"request\":{\"uri\":\"/opentracing\",\"url\":\"http://127.0.0.1:1984/opentracing\",\"querystring\":{},\"method\":\"GET\",\"size\":155,\"headers\":{\"content-type\":\"application/x-www-form-urlencoded\",\"host\":\"127.0.0.1:1984\",\"user-agent\":\"lua-resty-http/0.16.1 (Lua) ngx_lua/10025\"}},\"upstream\":\"127.0.0.1:1982\",\"apisix_latency\":100.99999809265,\"service_id\":\"\",\"upstream_latency\":1,\"start_time\":1704508259044,\"client_ip\":\"127.0.0.1\",\"latency\":101.99999809265}\n"
```

## Metadata

You can also set the format of the logs by configuring the Plugin metadata. The following configurations are available:

| Name       | Type   | Required | Default                                                                       | Description                                                                                                                                                                                                                                             |
| ---------- | ------ | -------- | ----------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| log_format | object | False    |  | Log format declared as key-value pairs in JSON. Values support strings and nested objects (up to five levels deep; deeper fields are truncated). Within strings, [APISIX](../apisix-variable.md) or [NGINX](http://nginx.org/en/docs/varindex.html) variables can be referenced by prefixing with `$`. |

:::info IMPORTANT

Configuring the Plugin metadata is global in scope. This means that it will take effect on all Routes and Services which use the `syslog` Plugin.

:::

The example below shows how you can configure through the Admin API:

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/syslog -H "X-API-KEY: $admin_key" -X PUT -d '
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

The example below shows how you can enable the Plugin for a specific Route:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "plugins": {
        "syslog": {
                "host" : "127.0.0.1",
                "port" : 5044,
                "flush_limit" : 1
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

Now, if you make a request to APISIX, it will be logged in your Syslog server:

```shell
curl -i http://127.0.0.1:9080/hello
```

## Delete Plugin

To remove the `syslog` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  -H "X-API-KEY: $admin_key" -X PUT -d '
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
