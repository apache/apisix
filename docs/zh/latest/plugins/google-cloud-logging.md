---
title: google-cloud-logging
keywords:
  - APISIX
  - API 网关
  - 插件
  - Google Cloud logging
  - 日志
description: API 网关 Apache APISIX 的 google-cloud-logging 插件可用于将请求日志转发到 Google Cloud Logging Service 中进行分析和存储。
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

## 描述

`google-cloud-logging` 插件可用于将请求日志发送到 [Google Cloud Logging Service](https://cloud.google.com/logging/) 进行分析和存储。

## 属性

| 名称                     | 必选项   | 默认值                                           | 描述                                                                                                                             |
| ----------------------- | -------- | ------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------  |
| auth_config             | 是       |                                                  | `auth_config` 和 `auth_file` 必须配置一个。                                                                                     |
| auth_config.client_email | 是       |                                                  | 谷歌服务帐号的 email 参数。                                                                                                           |
| auth_config.private_key | 是       |                                                  | 谷歌服务帐号的私钥参数。                                                                                                           |
| auth_config.project_id  | 是       |                                                  | 谷歌服务帐号的项目 ID。                                                                                                            |
| auth_config.token_uri   | 是       | https://oauth2.googleapis.com/token              | 请求谷歌服务帐户的令牌的 URI。                                                                                                     |
| auth_config.entries_uri | 否       | https://logging.googleapis.com/v2/entries:write  | 谷歌日志服务写入日志条目的 API。                                                                                                   |
| auth_config.scope       | 否       |                                                  | 谷歌服务账号的访问范围，可参考 [OAuth 2.0 Scopes for Google APIs](https://developers.google.com/identity/protocols/oauth2/scopes#logging)。可选项："https://www.googleapis.com/auth/logging.read"、"https://www.googleapis.com/auth/logging.write"、"https://www.googleapis.com/auth/logging.admin"、"https://www.googleapis.com/auth/cloud-platform"。|
| auth_config.scopes      | 废弃     |                                                  | 谷歌服务账号的访问范围，推荐使用 `auth_config.scope`                                                                               |
| auth_file               | 是       |                                                  | `auth_config` 和 `auth_file` 必须配置一个。                                                                 |
| ssl_verify              | 否       | true                                             | 当设置为 `true` 时，启用 `SSL` 验证。                 |
| resource                | 否       | {"type": "global"}                               | 谷歌监控资源，请参考 [MonitoredResource](https://cloud.google.com/logging/docs/reference/v2/rest/v2/MonitoredResource)。             |
| log_id                  | 否       | apisix.apache.org%2Flogs                         | 谷歌日志 ID，请参考 [LogEntry](https://cloud.google.com/logging/docs/reference/v2/rest/v2/LogEntry)。                                |
| log_format              | 否   |       | 日志格式以 JSON 的键值对声明。值支持字符串和嵌套对象（最多五层，超出部分将被截断）。字符串中可通过在前面加上 `$` 来引用 [APISIX 变量](../apisix-variable.md) 或 [NGINX 内置变量](http://nginx.org/en/docs/varindex.html)。 |

注意：schema 中还定义了 `encrypt_fields = {"auth_config.private_key"}`，这意味着该字段将会被加密存储在 etcd 中。具体参考 [加密存储字段](../plugin-develop.md#加密存储字段)。

该插件支持使用批处理器来聚合并批量处理条目（日志和数据）。这样可以避免该插件频繁地提交数据。默认情况下每 `5` 秒钟或队列中的数据达到 `1000` 条时，批处理器会自动提交数据，如需了解更多信息或自定义配置，请参考 [Batch Processor](../batch-processor.md#配置)。

### 默认日志格式示例

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

## 插件元数据

| 名称             | 类型    | 必选项 | 默认值        | 有效值  | 描述                                             |
| ---------------- | ------- | ------ | ------------- | ------- | ------------------------------------------------ |
| log_format       | object  | 否    |  |         | 日志格式以 JSON 的键值对声明。值支持字符串和嵌套对象（最多五层，超出部分将被截断）。字符串中可通过在前面加上 `$` 来引用 [APISIX 变量](../apisix-variable.md) 或 [NGINX 内置变量](http://nginx.org/en/docs/varindex.html)。 |
| max_pending_entries | integer | 否 | | | 在批处理器中开始删除待处理条目之前可以购买的最大待处理条目数。|

:::info 注意

该设置全局生效。如果指定了 `log_format`，则所有绑定 `google-cloud-logging` 的路由或服务都将使用该日志格式。

:::

以下示例展示了如何通过 Admin API 配置插件元数据：

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/google-cloud-logging \
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

配置完成后，你将在日志系统中看到如下类似日志：

```json
{"partialSuccess":false,"entries":[{"jsonPayload":{"host":"localhost","client_ip":"127.0.0.1","@timestamp":"2023-01-09T14:47:25+08:00","request":{"method":"GET","uri":"/hello"},"response":{"status":200},"route_id":"1"},"resource":{"type":"global"},"insertId":"942e81f60b9157f0d46bc9f5a8f0cc40","logName":"projects/apisix/logs/apisix.apache.org%2Flogs","timestamp":"2023-01-09T14:47:25+08:00","labels":{"source":"apache-apisix-google-cloud-logging"}}]}
```

## 启用插件

以下示例展示了如何在指定路由上启用该插件：

**完整配置**

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
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

**最小化配置**

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
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

## 测试插件

你可以通过以下命令向 APISIX 发出请求：

```shell
curl -i http://127.0.0.1:9080/hello
```

```
HTTP/1.1 200 OK
...
hello, world
```

访问成功后，你可以登录 [Google Cloud Logging Service](https://console.cloud.google.com/logs/viewer) 查看相关日志。

## 删除插件

当你需要删除该插件时，可以通过如下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

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
