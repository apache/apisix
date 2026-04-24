---
title: google-cloud-logging
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - Google Cloud logging
description: This document contains information about the Apache APISIX google-cloud-logging Plugin.
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

The `google-cloud-logging` Plugin is used to send APISIX access logs to [Google Cloud Logging Service](https://cloud.google.com/logging/).

This plugin also allows to push logs as a batch to your Google Cloud Logging Service. It might take some time to receive the log data. It will be automatically sent after the timer function in the [batch processor](../batch-processor.md) expires.

## Attributes

| Name                    | Required | Default                                                                                                                                                                                              | Description                                                                                                                                                        |
|-------------------------|----------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| auth_config             | True     |                                                                                                                                                                                                      | Either `auth_config` or `auth_file` must be provided.                                                                                                              |
| auth_config.client_email | True     |                                                                                                                                                                                                    | Email address of the Google Cloud service account.                                                                                                                   |
| auth_config.private_key | True     |                                                                                                                                                                                                      | Private key of the Google Cloud service account.                                                                                                                   |
| auth_config.project_id  | True     |                                                                                                                                                                                                      | Project ID in the Google Cloud service account.                                                                                                                    |
| auth_config.token_uri   | True    | https://oauth2.googleapis.com/token                                                                                                                                                                  | Token URI of the Google Cloud service account.                                                                                                                     |
| auth_config.entries_uri | False    | https://logging.googleapis.com/v2/entries:write                                                                                                                                                      | Google Cloud Logging Service API.                                                                                                                                  |
| auth_config.scope       | False    | ["https://www.googleapis.com/auth/logging.read", "https://www.googleapis.com/auth/logging.write", "https://www.googleapis.com/auth/logging.admin", "https://www.googleapis.com/auth/cloud-platform"] | Access scopes of the Google Cloud service account. See [OAuth 2.0 Scopes for Google APIs](https://developers.google.com/identity/protocols/oauth2/scopes#logging). |
| auth_config.scopes      | Deprecated    | ["https://www.googleapis.com/auth/logging.read", "https://www.googleapis.com/auth/logging.write", "https://www.googleapis.com/auth/logging.admin", "https://www.googleapis.com/auth/cloud-platform"] | Access scopes of the Google Cloud service account. Use `auth_config.scope` instead.                                                                           |
| auth_file               | True     |                                                                                                                                                                                                      | Path to the Google Cloud service account authentication JSON file. Either `auth_config` or `auth_file` must be provided.                                           |
| ssl_verify              | False    | true                                                                                                                                                                                                 | When set to `true`, enables SSL verification as mentioned in [OpenResty docs](https://github.com/openresty/lua-nginx-module#tcpsocksslhandshake).                  |
| resource                | False    | {"type": "global"}                                                                                                                                                                                   | Google monitor resource. See [MonitoredResource](https://cloud.google.com/logging/docs/reference/v2/rest/v2/MonitoredResource) for more details.                   |
| log_id                  | False    | apisix.apache.org%2Flogs                                                                                                                                                                             | Google Cloud logging ID. See [LogEntry](https://cloud.google.com/logging/docs/reference/v2/rest/v2/LogEntry) for details.                                          |
| log_format              | False    |                            | Log format declared as key-value pairs in JSON. Values support strings and nested objects (up to five levels deep; deeper fields are truncated). Within strings, [APISIX](../apisix-variable.md) or [NGINX](http://nginx.org/en/docs/varindex.html) variables can be referenced by prefixing with `$`. |

NOTE: `encrypt_fields = {"auth_config.private_key"}` is also defined in the schema, which means that the field will be stored encrypted in etcd. See [encrypted storage fields](../plugin-develop.md#encrypted-storage-fields).

This Plugin supports using batch processors to aggregate and process entries (logs/data) in a batch. This avoids the need for frequently submitting the data. The batch processor submits data every `5` seconds or when the data in the queue reaches `1000`. See [Batch Processor](../batch-processor.md#configuration) for more information or setting your custom configuration.

### Example of default log format

```json
{
    "insertId": "0013a6afc9c281ce2e7f413c01892bdc",
    "labels": {
        "source": "apache-apisix-google-cloud-logging"
    },
    "logName": "projects/apisix/logs/apisix.apache.org%2Flogs",
    "httpRequest": {
        "requestMethod": "GET",
        "requestUrl": "http://localhost:1984/hello",
        "requestSize": 59,
        "responseSize": 118,
        "status": 200,
        "remoteIp": "127.0.0.1",
        "serverIp": "127.0.0.1:1980",
        "latency": "0.103s"
    },
    "resource": {
        "type": "global"
    },
    "jsonPayload": {
        "service_id": "",
        "route_id": "1"
    },
    "timestamp": "2024-01-06T03:34:45.065Z"
}
```

## Metadata

You can also set the format of the logs by configuring the Plugin metadata. The following configurations are available:

| Name       | Type   | Required | Default                                                                       | Description                                                                                                                                                                                                                                             |
| ---------- | ------ | -------- | ----------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| log_format | object | False    |  | Log format declared as key-value pairs in JSON. Values support strings and nested objects (up to five levels deep; deeper fields are truncated). Within strings, [APISIX](../apisix-variable.md) or [NGINX](http://nginx.org/en/docs/varindex.html) variables can be referenced by prefixing with `$`. |
| max_pending_entries | integer | False | | Maximum number of pending entries that can be buffered in batch processor before it starts dropping them. |

:::info IMPORTANT

Configuring the Plugin metadata is global in scope. This means that it will take effect on all Routes and Services which use the `google-cloud-logging` Plugin.

:::

The example below shows how you can configure through the Admin API:

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/google-cloud-logging -H "X-API-KEY: $admin_key" -X PUT -d '
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

```json
{"partialSuccess":false,"entries":[{"jsonPayload":{"host":"localhost","client_ip":"127.0.0.1","@timestamp":"2023-01-09T14:47:25+08:00","request":{"method":"GET","uri":"/hello"},"response":{"status":200},"route_id":"1"},"resource":{"type":"global"},"insertId":"942e81f60b9157f0d46bc9f5a8f0cc40","logName":"projects/apisix/logs/apisix.apache.org%2Flogs","timestamp":"2023-01-09T14:47:25+08:00","labels":{"source":"apache-apisix-google-cloud-logging"}}]}
```

## Enable Plugin

### Full configuration

The example below shows a complete configuration of the Plugin on a specific Route:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "plugins": {
        "google-cloud-logging": {
            "auth_config":{
                "project_id":"apisix",
                "client_email":"your service account email@apisix.iam.gserviceaccount.com",
                "private_key":"-----BEGIN RSA PRIVATE KEY-----your private key-----END RSA PRIVATE KEY-----",
                "token_uri":"https://oauth2.googleapis.com/token",
                "scope":[
                    "https://www.googleapis.com/auth/logging.admin"
                ],
                "entries_uri":"https://logging.googleapis.com/v2/entries:write"
            },
            "resource":{
                "type":"global"
            },
            "log_id":"apisix.apache.org%2Flogs",
            "inactive_timeout":10,
            "max_retry_count":0,
            "buffer_duration":60,
            "retry_delay":1,
            "batch_max_size":1
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

### Minimal configuration

The example below shows a bare minimum configuration of the Plugin on a Route:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "plugins": {
        "google-cloud-logging": {
            "auth_config":{
                "project_id":"apisix",
                "client_email":"your service account email@apisix.iam.gserviceaccount.com",
                "private_key":"-----BEGIN RSA PRIVATE KEY-----your private key-----END RSA PRIVATE KEY-----"
            }
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

Now, if you make a request to APISIX, it will be logged in your Google Cloud Logging Service.

```shell
curl -i http://127.0.0.1:9080/hello
```

You can then login and view the logs in [Google Cloud Logging Service](https://console.cloud.google.com/logs/viewer).

## Delete Plugin

To remove the `google-cloud-logging` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
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
