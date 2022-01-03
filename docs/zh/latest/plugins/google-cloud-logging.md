---
title: google-cloud-logging
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

## 摘要

- [**定义**](#定义)
- [**属性列表**](#属性列表)
- [**如何开启**](#如何开启)
- [**测试插件**](#测试插件)
- [**禁用插件**](#禁用插件)

## 定义

`google-cloud-logging` 插件用于将 `Apache APISIX` 的请求日志发送到 [Google Cloud Logging Service](https://cloud.google.com/logging/)。

该插件提供了将请求的日志数据以批处理队列的形式推送到谷歌云日志服务的功能。

有关 `Apache APISIX` 的 `Batch-Processor` 的更多信息，请参考：
[Batch-Processor](../batch-processor.md)

## 属性列表

| 名称                  | 是否必需 | 默认值                                                                                                                                                                                         | 描述                                                                                                                                     |
| ----------------------- | -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| auth_config             | 半可选 |                                                                                                                                                                                                   | 必须配置 `auth_config` 或 `auth_file` 之一                                                                                          |
| auth_config.private_key | 必选   |                                                                                                                                                                                                   | 谷歌服务帐号的私钥参数                                                                                                          |
| auth_config.project_id  | 必选   |                                                                                                                                                                                                   | 谷歌服务帐号的项目ID                                                                                                             |
| auth_config.token_uri   | 可选   | https://oauth2.googleapis.com/token                                                                                                                                                               | 请求谷歌服务帐户的令牌的URI                                                                                                  |
| auth_config.entries_uri | 可选   | https://logging.googleapis.com/v2/entries:write                                                                                                                                                   | 谷歌日志服务写入日志条目的API                                                                                                 |
| auth_config.scopes      | 可选   | ["https://www.googleapis.com/auth/logging.read","https://www.googleapis.com/auth/logging.write","https://www.googleapis.com/auth/logging.admin","https://www.googleapis.com/auth/cloud-platform"] | 谷歌服务账号的访问范围, 参考: [OAuth 2.0 Scopes for Google APIs](https://developers.google.com/identity/protocols/oauth2/scopes#logging) |
| auth_file               | 半可选 |                                                                                                                                                                                                   | 谷歌服务账号JSON文件的路径（必须配置 `auth_config` 或 `auth_file` 之一）                                                   |
| ssl_verify              | 可选   | true                                                                                                                                                                                              | 启用 `SSL` 验证, 配置根据 [OpenResty文档](https://github.com/openresty/lua-nginx-module#tcpsocksslhandshake) 选项|
| resource                | 可选   | {"type": "global"}                                                                                                                                                                                | 谷歌监控资源，参考： [MonitoredResource](https://cloud.google.com/logging/docs/reference/v2/rest/v2/MonitoredResource)           |
| log_id                  | 可选   | apisix.apache.org%2Flogs                                                                                                                                                                          | 谷歌日志ID，参考： [LogEntry](https://cloud.google.com/logging/docs/reference/v2/rest/v2/LogEntry)                                 |
| max_retry_count         | 可选   | 0                                                                                                                                                                                                 | 从处理管道中移除之前的最大重试次数                                                                                        |
| retry_delay             | 可选   | 1                                                                                                                                                                                                 | 如果执行失败，流程执行应延迟的秒数                                                                                        |
| buffer_duration         | 可选   | 60                                                                                                                                                                                                | 必须先处理批次中最旧条目的最大期限（以秒为单位）                                                                   |
| inactive_timeout        | 可选   | 5                                                                                                                                                                                                 | 刷新缓冲区的最大时间（以秒为单位）                                                                                        |
| batch_max_size          | 可选   | 1000                                                                                                                                                                                              | 每个批处理队列可容纳的最大条目数                                                                                                                      |

## 如何开启

下面例子展示了如何为指定路由开启 `google-cloud-logging` 插件。

### 完整配置

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

### 最小化配置

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

* 向配置 `google-cloud-logging` 插件的路由发送请求

```shell
$ curl -i http://127.0.0.1:9080/hello
HTTP/1.1 200 OK
...
hello, world
```

* 登录谷歌云日志服务，查看日志

[Google Cloud Logging Service](https://console.cloud.google.com/logs/viewer)

## 禁用插件

禁用 `google-cloud-logging` 插件非常简单，只需将 `google-cloud-logging` 对应的 `JSON` 配置移除即可。

```shell
$ curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
