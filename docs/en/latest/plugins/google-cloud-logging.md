---
title: google-cloud-logging
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - Google Cloud logging
description: The google-cloud-logging Plugin pushes request and response logs in batches to Google Cloud Logging Service and supports the customization of log formats.
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

<head>
  <link rel="canonical" href="https://docs.api7.ai/hub/google-cloud-logging" />
</head>

## Description

The `google-cloud-logging` Plugin pushes request and response logs in batches to [Google Cloud Logging Service](https://cloud.google.com/logging?hl=en) and supports the customization of log formats.

## Attributes

| Name                    | Type          | Required | Default                                                                                                                                                                                              | Valid values | Description                                                                                                                                                                                                                                                                                          |
|-------------------------|---------------|----------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|--------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| auth_config             | object        | False    |                                                                                                                                                                                                      | | Authentication configurations. At least one of `auth_config` and `auth_file` must be provided.                                                                                                                                                                                                      |
| auth_config.client_email | string       | True     |                                                                                                                                                                                                      | | Email address of the Google Cloud service account.                                                                                                                                                                                                                                                   |
| auth_config.private_key | string        | True     |                                                                                                                                                                                                      | | Private key of the Google Cloud service account.                                                                                                                                                                                                                                                     |
| auth_config.project_id  | string        | True     |                                                                                                                                                                                                      | | Project ID in the Google Cloud service account.                                                                                                                                                                                                                                                      |
| auth_config.token_uri   | string        | True     | https://oauth2.googleapis.com/token                                                                                                                                                                  | | Token URI of the Google Cloud service account.                                                                                                                                                                                                                                                       |
| auth_config.entries_uri | string        | False    | https://logging.googleapis.com/v2/entries:write                                                                                                                                                      | | Google Cloud Logging Service API.                                                                                                                                                                                                                                                                    |
| auth_config.scope       | array[string] | False    | ["https://www.googleapis.com/auth/logging.read", "https://www.googleapis.com/auth/logging.write", "https://www.googleapis.com/auth/logging.admin", "https://www.googleapis.com/auth/cloud-platform"] | | Access scopes of the Google Cloud service account. See [OAuth 2.0 Scopes for Google APIs](https://developers.google.com/identity/protocols/oauth2/scopes#logging).                                                                                                                                  |
| auth_file               | string        | False    |                                                                                                                                                                                                      | | Path to the Google Cloud service account authentication JSON file. At least one of `auth_config` and `auth_file` must be provided.                                                                                                                                                                   |
| ssl_verify              | boolean       | False    | true                                                                                                                                                                                                 | | If `true`, verifies the server's SSL certificate.                                                                                                                                                                                                                                                    |
| resource                | object        | False    | {"type": "global"}                                                                                                                                                                                   | | Google monitored resource. See [MonitoredResource](https://cloud.google.com/logging/docs/reference/v2/rest/v2/MonitoredResource) for more details.                                                                                                                                                   |
| log_id                  | string        | False    | apisix.apache.org%2Flogs                                                                                                                                                                             | | Google Cloud logging ID. See [LogEntry](https://cloud.google.com/logging/docs/reference/v2/rest/v2/LogEntry) for details.                                                                                                                                                                            |
| log_format              | object        | False    |                                                                                                                                                                                                      | | Custom log format using key-value pairs in JSON format. Values can reference [APISIX variables](../apisix-variable.md) or [NGINX variables](https://nginx.org/en/docs/http/ngx_http_core_module.html) by prefixing with `$`. You can also configure log format on a global scale using [Plugin Metadata](#plugin-metadata). |
| name                    | string        | False    | google-cloud-logging                                                                                                                                                                                 | | Unique identifier of the Plugin for the batch processor. If you use [Prometheus](./prometheus.md) to monitor APISIX metrics, the name is exported in `apisix_batch_process_entries`.                                                                                                                 |
| batch_max_size          | integer       | False    | 1000                                                                                                                                                                                                 | | The number of log entries allowed in one batch. Once reached, the batch will be sent to the logging service. Setting this parameter to `1` means immediate processing.                                                                                                                               |
| inactive_timeout        | integer       | False    | 5                                                                                                                                                                                                    | | The maximum time in seconds to wait for new logs before sending the batch to the logging service. The value should be smaller than `buffer_duration`.                                                                                                                                                |
| buffer_duration         | integer       | False    | 60                                                                                                                                                                                                   | | The maximum time in seconds from the earliest entry allowed before sending the batch to the logging service.                                                                                                                                                                                         |
| retry_delay             | integer       | False    | 1                                                                                                                                                                                                    | | The time interval in seconds to retry sending the batch to the logging service if the batch was not successfully sent.                                                                                                                                                                               |
| max_retry_count         | integer       | False    | 0                                                                                                                                                                                                   | | The maximum number of unsuccessful retries allowed before dropping the log entries.                                                                                                                                                                                                                  |

NOTE: `encrypt_fields = {"auth_config.private_key"}` is also defined in the schema, which means that the field will be stored encrypted in etcd. See [encrypted storage fields](../plugin-develop.md#encrypted-storage-fields).

This Plugin supports using batch processors to aggregate and process entries (logs/data) in a batch. This avoids the need for frequently submitting the data. The batch processor submits data every `5` seconds or when the data in the queue reaches `1000`. See [Batch Processor](../batch-processor.md#configuration) for more information or setting your custom configuration.

## Plugin Metadata

| Name               | Type    | Required | Default | Valid values | Description                                                                                                                                                                                                                                                                     |
|--------------------|---------|----------|---------|--------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| log_format         | object  | False    |         |              | Custom log format using key-value pairs in JSON format. Values can reference [APISIX variables](../apisix-variable.md) or [NGINX variables](https://nginx.org/en/docs/http/ngx_http_core_module.html) by prefixing with `$`. This configuration is global and applies to all Routes and Services that use the `google-cloud-logging` Plugin. |
| max_pending_entries | integer | False   |         | >= 1         | Maximum number of unprocessed entries allowed in the batch processor. When this limit is reached, new entries will be dropped until the backlog is reduced.                                                                                                                      |

## Examples

The examples below demonstrate how you can configure the `google-cloud-logging` Plugin for different use cases.

To follow along with the examples, you should have a GCP account with active billing. You should also first obtain authentication credentials in GCP by completing the following steps:

* Visit **IAM & Admin** to create a service account.
* Assign the service account with the **Logs Writer** role, which assigns the account with `logging.logEntries.create` and `logging.logEntries.route` permissions.
* Create a private key for the service account and download the credentials in JSON format.

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Configure Authentication Using `auth_config`

The following example demonstrates how to configure the `google-cloud-logging` Plugin on a Route using the `auth_config` option to provide GCP authentication details inline.

Create a Route with `google-cloud-logging`, replacing `client_email`, `project_id`, `private_key`, and `token_uri` with your service account details:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "google-cloud-logging-route",
    "uri": "/anything",
    "plugins": {
      "google-cloud-logging": {
        "auth_config": {
          "client_email": "your-service-account@your-project.iam.gserviceaccount.com",
          "project_id": "your-project-id",
          "private_key": "-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n",
          "token_uri": "https://oauth2.googleapis.com/token"
        }
      }
    },
    "upstream": {
      "nodes": {
        "httpbin.org:80": 1
      },
      "type": "roundrobin"
    }
  }'
```

Send a request to the Route to generate a log entry:

```shell
curl -i "http://127.0.0.1:9080/anything"
```

You should receive an `HTTP/1.1 200 OK` response.

Navigate to Google Cloud Logs Explorer. You should see a log entry corresponding to your request, similar to the following:

```json
{
  "insertId": "5400340ea330b35f2d557da2cbb9e88d",
  "jsonPayload": {
    "service_id": "",
    "route_id": "google-cloud-logging-route"
  },
  "httpRequest": {
    "requestMethod": "GET",
    "requestUrl": "http://127.0.0.1:9080/anything",
    "requestSize": "85",
    "status": 200,
    "responseSize": "615",
    "userAgent": "curl/8.6.0",
    "remoteIp": "192.168.107.1",
    "serverIp": "54.86.137.185:80",
    "latency": "1.083s"
  },
  "resource": {
    "type": "global",
    "labels": {
      "project_id": "your-project-id"
    }
  },
  "timestamp": "2025-02-07T07:39:51.859Z",
  "labels": {
    "source": "apache-apisix-google-cloud-logging"
  },
  "logName": "projects/your-project-id/logs/apisix.apache.org%2Flogs",
  "receiveTimestamp": "2025-02-07T07:39:58.012811475Z"
}
```

### Configure Authentication Using `auth_file`

The following example demonstrates how to configure the `google-cloud-logging` Plugin on a Route using the `auth_file` option to reference a GCP service account credentials file.

Copy the previously downloaded GCP service account credentials JSON file to a location accessible for APISIX. If you are running APISIX in Docker, copy the file into the container, for instance, to `/usr/local/apisix/conf/gcp-logging-auth.json`.

Create a Route with `google-cloud-logging`, replacing the `auth_file` path with the path to your credentials file:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "google-cloud-logging-route",
    "uri": "/anything",
    "plugins": {
      "google-cloud-logging": {
        "auth_file": "/usr/local/apisix/conf/gcp-logging-auth.json"
      }
    },
    "upstream": {
      "nodes": {
        "httpbin.org:80": 1
      },
      "type": "roundrobin"
    }
  }'
```

Send a request to the Route to generate a log entry:

```shell
curl -i "http://127.0.0.1:9080/anything"
```

You should receive an `HTTP/1.1 200 OK` response.

Navigate to Google Cloud Logs Explorer. You should see a log entry corresponding to your request, similar to the following:

```json
{
  "insertId": "5400340ea330b35f2d557da2cbb9e88d",
  "jsonPayload": {
    "service_id": "",
    "route_id": "google-cloud-logging-route"
  },
  "httpRequest": {
    "requestMethod": "GET",
    "requestUrl": "http://127.0.0.1:9080/anything",
    "requestSize": "85",
    "status": 200,
    "responseSize": "615",
    "userAgent": "curl/8.6.0",
    "remoteIp": "192.168.107.1",
    "serverIp": "54.86.137.185:80",
    "latency": "1.083s"
  },
  "resource": {
    "type": "global",
    "labels": {
      "project_id": "your-project-id"
    }
  },
  "timestamp": "2025-02-07T08:25:11.325Z",
  "labels": {
    "source": "apache-apisix-google-cloud-logging"
  },
  "logName": "projects/your-project-id/logs/apisix.apache.org%2Flogs",
  "receiveTimestamp": "2025-02-07T08:25:11.423190575Z"
}
```

### Customize Log Format With Plugin Metadata

The following example demonstrates how to customize the log format using Plugin Metadata and [NGINX variables](https://nginx.org/en/docs/http/ngx_http_core_module.html) to log specific headers from request and response.

Plugin Metadata is global in scope and applies to all instances of `google-cloud-logging`. If the log format configured on an individual Plugin instance differs from the log format configured in Plugin Metadata, the instance-level configuration takes precedence.

First, create a Route with `google-cloud-logging`, replacing credentials with your own:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "google-cloud-logging-route",
    "uri": "/anything",
    "plugins": {
      "google-cloud-logging": {
        "auth_config": {
          "client_email": "your-service-account@your-project.iam.gserviceaccount.com",
          "project_id": "your-project-id",
          "private_key": "-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n",
          "token_uri": "https://oauth2.googleapis.com/token"
        }
      }
    },
    "upstream": {
      "nodes": {
        "httpbin.org:80": 1
      },
      "type": "roundrobin"
    }
  }'
```

Configure Plugin Metadata for `google-cloud-logging`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/plugin_metadata/google-cloud-logging" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "log_format": {
      "host": "$host",
      "@timestamp": "$time_iso8601",
      "client_ip": "$remote_addr"
    }
  }'
```

Send a request to the Route:

```shell
curl -i "http://127.0.0.1:9080/anything"
```

You should receive an `HTTP/1.1 200 OK` response.

Navigate to Google Cloud Logs Explorer. You should see a log entry corresponding to your request, similar to the following:

```json
{
  "@timestamp":"2025-02-07T09:10:42+00:00",
  "client_ip":"192.168.107.1",
  "host":"127.0.0.1",
  "route_id":"google-cloud-logging-route"
}
```

The log format configured in Plugin Metadata is effective for all instances of `google-cloud-logging` when no `log_format` is specified on the individual instance.

If you configure `log_format` directly on the Route's Plugin instance, it takes precedence over Plugin Metadata. For example, to additionally log the custom request header `env` and response header `Content-Type`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/google-cloud-logging-route" -X PATCH \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "plugins": {
      "google-cloud-logging": {
        "log_format": {
          "host": "$host",
          "@timestamp": "$time_iso8601",
          "client_ip": "$remote_addr",
          "env": "$http_env",
          "resp_content_type": "$sent_http_Content_Type"
        }
      }
    }
  }'
```

Send a request to the Route with the `env` header:

```shell
curl -i "http://127.0.0.1:9080/anything" -H "env: dev"
```

You should receive an `HTTP/1.1 200 OK` response.

Navigate to Google Cloud Logs Explorer. You should see a log entry corresponding to your request, similar to the following:

```json
{
  "@timestamp":"2025-02-07T09:38:55+00:00",
  "client_ip":"192.168.107.1",
  "host":"127.0.0.1",
  "env":"dev",
  "resp_content_type":"application/json",
  "route_id":"google-cloud-logging-route"
}
```
