---
title: google-cloud-logging
keywords:
  - APISIX
  - API 网关
  - 插件
  - Splunk
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
| auth_config.private_key | 是       |                                                  | 谷歌服务帐号的私钥参数。                                                                                                           |
| auth_config.project_id  | 是       |                                                  | 谷歌服务帐号的项目 ID。                                                                                                            |
| auth_config.token_uri   | 是       | https://oauth2.googleapis.com/token              | 请求谷歌服务帐户的令牌的 URI。                                                                                                     |
| auth_config.entries_uri | 否       | https://logging.googleapis.com/v2/entries:write  | 谷歌日志服务写入日志条目的 API。                                                                                                   |
| auth_config.scopes      | 否       |                                                  | 谷歌服务账号的访问范围，可参考 [OAuth 2.0 Scopes for Google APIs](https://developers.google.com/identity/protocols/oauth2/scopes#logging)。可选项："https://www.googleapis.com/auth/logging.read"、"https://www.googleapis.com/auth/logging.write"、"https://www.googleapis.com/auth/logging.admin"、"https://www.googleapis.com/auth/cloud-platform"。|
| auth_file               | 是       |                                                  | `auth_config` 和 `auth_file` 必须配置一个。                                                                 |
| ssl_verify              | 否       | true                                             | 当设置为 `true` 时，启用 `SSL` 验证。                 |
| resource                | 否       | {"type": "global"}                               | 谷歌监控资源，请参考 [MonitoredResource](https://cloud.google.com/logging/docs/reference/v2/rest/v2/MonitoredResource)。             |
| log_id                  | 否       | apisix.apache.org%2Flogs                         | 谷歌日志 ID，请参考 [LogEntry](https://cloud.google.com/logging/docs/reference/v2/rest/v2/LogEntry)。                                |

注意：schema 中还定义了 `encrypt_fields = {"auth_config.private_key"}`，这意味着该字段将会被加密存储在 etcd 中。具体参考 [加密存储字段](../plugin-develop.md#加密存储字段)。

该插件支持使用批处理器来聚合并批量处理条目（日志和数据）。这样可以避免该插件频繁地提交数据。默认情况下每 `5` 秒钟或队列中的数据达到 `1000` 条时，批处理器会自动提交数据，如需了解更多信息或自定义配置，请参考 [Batch Processor](../batch-processor.md#配置)。

## 启用插件

以下示例展示了如何在指定路由上启用该插件：

**完整配置**

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "plugins": {
        "google-cloud-logging": {
            "auth_config":{
                "project_id":"apisix",
                "private_key":"-----BEGIN RSA PRIVATE KEY-----your private key-----END RSA PRIVATE KEY-----",
                "token_uri":"https://oauth2.googleapis.com/token",
                "scopes":[
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
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "plugins": {
        "google-cloud-logging": {
            "auth_config":{
                "project_id":"apisix",
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

## 禁用插件

当你需要禁用该插件时，可以通过如下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

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
