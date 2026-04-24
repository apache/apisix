---
title: google-cloud-logging
keywords:
  - APISIX
  - API 网关
  - Plugin
  - Google Cloud logging
description: google-cloud-logging 插件将请求和响应日志批量推送到 Google Cloud Logging Service，并支持自定义日志格式。
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

## 描述

`google-cloud-logging` 插件将请求和响应日志批量推送到 [Google Cloud Logging Service](https://cloud.google.com/logging?hl=en)，并支持自定义日志格式。

## 属性

| 名称                    | 类型          | 必选项 | 默认值                                                                                                                                                                                                 | 有效值 | 描述                                                                                                                                                                                                                                                                                                |
|-------------------------|---------------|--------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|--------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| auth_config             | object        | False  |                                                                                                                                                                                                        | | 认证配置。`auth_config` 和 `auth_file` 中至少需要提供一个。                                                                                                                                                                                                                                         |
| auth_config.client_email | string       | True   |                                                                                                                                                                                                        | | Google Cloud 服务账号的电子邮件地址。                                                                                                                                                                                                                                                               |
| auth_config.private_key | string        | True   |                                                                                                                                                                                                        | | Google Cloud 服务账号的私钥。                                                                                                                                                                                                                                                                       |
| auth_config.project_id  | string        | True   |                                                                                                                                                                                                        | | Google Cloud 服务账号中的项目 ID。                                                                                                                                                                                                                                                                  |
| auth_config.token_uri   | string        | True   | https://oauth2.googleapis.com/token                                                                                                                                                                    | | Google Cloud 服务账号的 Token URI。                                                                                                                                                                                                                                                                 |
| auth_config.entries_uri | string        | False  | https://logging.googleapis.com/v2/entries:write                                                                                                                                                        | | Google Cloud Logging Service API。                                                                                                                                                                                                                                                                  |
| auth_config.scope       | array[string] | False  | ["https://www.googleapis.com/auth/logging.read", "https://www.googleapis.com/auth/logging.write", "https://www.googleapis.com/auth/logging.admin", "https://www.googleapis.com/auth/cloud-platform"] | | Google Cloud 服务账号的访问范围。参见 [OAuth 2.0 Scopes for Google APIs](https://developers.google.com/identity/protocols/oauth2/scopes#logging)。                                                                                                                                                    |
| auth_file               | string        | False  |                                                                                                                                                                                                        | | Google Cloud 服务账号认证 JSON 文件的路径。`auth_config` 和 `auth_file` 中至少需要提供一个。                                                                                                                                                                                                        |
| ssl_verify              | boolean       | False  | true                                                                                                                                                                                                   | | 若为 `true`，则验证服务器的 SSL 证书。                                                                                                                                                                                                                                                              |
| resource                | object        | False  | {"type": "global"}                                                                                                                                                                                     | | Google 监控资源。详情参见 [MonitoredResource](https://cloud.google.com/logging/docs/reference/v2/rest/v2/MonitoredResource)。                                                                                                                                                                        |
| log_id                  | string        | False  | apisix.apache.org%2Flogs                                                                                                                                                                               | | Google Cloud 日志 ID。详情参见 [LogEntry](https://cloud.google.com/logging/docs/reference/v2/rest/v2/LogEntry)。                                                                                                                                                                                    |
| log_format              | object        | False  |                                                                                                                                                                                                        | | 以 JSON 键值对形式声明的自定义日志格式。值可通过 `$` 前缀引用 [APISIX 变量](../apisix-variable.md) 或 [NGINX 变量](https://nginx.org/en/docs/http/ngx_http_core_module.html)。也可通过[插件元数据](#插件元数据)全局配置日志格式。                                                                     |
| name                    | string        | False  | google-cloud-logging                                                                                                                                                                                   | | 批处理器中插件的唯一标识符。如果使用 [Prometheus](./prometheus.md) 监控 APISIX 指标，该名称将在 `apisix_batch_process_entries` 中导出。                                                                                                                                                              |
| batch_max_size          | integer       | False  | 1000                                                                                                                                                                                                   | | 单批允许的日志条目数。达到此数量后，批次将被发送至日志服务。设置为 `1` 表示立即处理。                                                                                                                                                                                                               |
| inactive_timeout        | integer       | False  | 5                                                                                                                                                                                                      | | 在发送批次到日志服务之前等待新日志的最长时间（秒）。该值应小于 `buffer_duration`。                                                                                                                                                                                                                  |
| buffer_duration         | integer       | False  | 60                                                                                                                                                                                                     | | 在发送批次到日志服务之前，允许最早条目存在的最长时间（秒）。                                                                                                                                                                                                                                        |
| retry_delay             | integer       | False  | 1                                                                                                                                                                                                      | | 批次发送失败后重试的时间间隔（秒）。                                                                                                                                                                                                                                                                |
| max_retry_count         | integer       | False  | 0                                                                                                                                                                                                     | | 在丢弃日志条目之前允许的最大重试次数。                                                                                                                                                                                                                                                              |

注意：schema 中还定义了 `encrypt_fields = {"auth_config.private_key"}`，这意味着该字段将会被加密存储在 etcd 中。具体参考[加密存储字段](../plugin-develop.md#加密存储字段)。

该插件支持使用批处理器来聚合并批量处理条目（日志/数据）。这样可以避免插件频繁地提交数据，默认情况下批处理器每 `5` 秒钟或队列中的数据达到 `1000` 条时提交数据。如需了解批处理器相关参数设置，请参考 [Batch-Processor](../batch-processor.md#配置)。

## 插件元数据

| 名称               | 类型    | 必选项 | 默认值 | 有效值 | 描述                                                                                                                                                                                                 |
|--------------------|---------|--------|--------|--------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| log_format         | object  | False  |        |        | 以 JSON 键值对形式声明的自定义日志格式。值可通过 `$` 前缀引用 [APISIX 变量](../apisix-variable.md) 或 [NGINX 变量](https://nginx.org/en/docs/http/ngx_http_core_module.html)。该配置全局生效，对所有绑定 `google-cloud-logging` 的路由和服务生效。 |
| max_pending_entries | integer | False |        | >= 1   | 批处理器中允许的最大未处理条目数。达到此限制后，新条目将被丢弃，直到积压减少。                                                                                                                         |

## 示例

以下示例演示了如何为不同场景配置 `google-cloud-logging` 插件。

按照示例操作，你需要一个已开通计费的 GCP 账号。请先在 GCP 中完成以下步骤获取认证凭证：

* 访问 **IAM & Admin** 创建一个服务账号。
* 为服务账号分配 **Logs Writer** 角色，该角色赋予账号 `logging.logEntries.create` 和 `logging.logEntries.route` 权限。
* 为服务账号创建私钥并以 JSON 格式下载凭证文件。

:::note

你可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### 使用 `auth_config` 配置认证

以下示例演示如何在路由上配置 `google-cloud-logging` 插件，使用 `auth_config` 选项内联提供 GCP 认证详情。

创建启用 `google-cloud-logging` 的路由，将 `client_email`、`project_id`、`private_key` 和 `token_uri` 替换为你的服务账号详情：

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

向路由发送请求以生成日志条目：

```shell
curl -i "http://127.0.0.1:9080/anything"
```

你应该收到 `HTTP/1.1 200 OK` 响应。

导航到 Google Cloud Logs Explorer，你应该看到对应请求的日志条目，类似如下：

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

### 使用 `auth_file` 配置认证

以下示例演示如何在路由上配置 `google-cloud-logging` 插件，使用 `auth_file` 选项引用 GCP 服务账号凭证文件。

将之前下载的 GCP 服务账号凭证 JSON 文件复制到 APISIX 可访问的位置。如果你在 Docker 中运行 APISIX，请将文件复制到容器中，例如复制到 `/usr/local/apisix/conf/gcp-logging-auth.json`。

创建启用 `google-cloud-logging` 的路由，将 `auth_file` 路径替换为你的凭证文件路径：

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

向路由发送请求以生成日志条目：

```shell
curl -i "http://127.0.0.1:9080/anything"
```

你应该收到 `HTTP/1.1 200 OK` 响应。

导航到 Google Cloud Logs Explorer，你应该看到对应请求的日志条目，类似如下：

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

### 使用插件元数据自定义日志格式

以下示例演示如何使用插件元数据和 [NGINX 变量](https://nginx.org/en/docs/http/ngx_http_core_module.html) 自定义日志格式，以记录请求和响应中的特定头信息。

插件元数据全局生效，对所有 `google-cloud-logging` 实例有效。如果单个插件实例上配置的日志格式与插件元数据中配置的日志格式不同，则实例级别的配置优先。

首先创建启用 `google-cloud-logging` 的路由，替换为你的凭证：

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

为 `google-cloud-logging` 配置插件元数据：

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

向路由发送请求：

```shell
curl -i "http://127.0.0.1:9080/anything"
```

你应该收到 `HTTP/1.1 200 OK` 响应。

导航到 Google Cloud Logs Explorer，你应该看到对应请求的日志条目，类似如下：

```json
{
  "@timestamp":"2025-02-07T09:10:42+00:00",
  "client_ip":"192.168.107.1",
  "host":"127.0.0.1",
  "route_id":"google-cloud-logging-route"
}
```

插件元数据中配置的日志格式对所有 `google-cloud-logging` 实例生效（当实例未指定 `log_format` 时）。

如果在路由的插件实例上直接配置 `log_format`，该配置将优先于插件元数据。例如，额外记录自定义请求头 `env` 和响应头 `Content-Type`：

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

向路由发送带有 `env` 头的请求：

```shell
curl -i "http://127.0.0.1:9080/anything" -H "env: dev"
```

你应该收到 `HTTP/1.1 200 OK` 响应。

导航到 Google Cloud Logs Explorer，你应该看到对应请求的日志条目，类似如下：

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
