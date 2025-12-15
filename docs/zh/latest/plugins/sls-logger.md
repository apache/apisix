---
title: sls-logger
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

`sls-logger` 是使用 [RF5424](https://tools.ietf.org/html/rfc5424) 标准将日志数据以 JSON 格式发送到 [阿里云日志服务](https://help.aliyun.com/document_detail/112903.html?spm=a2c4g.11186623.6.763.21321b47wcwt1u)。

该插件提供了将 Log Data 作为批处理推送到阿里云日志服务器的功能。如果您没有收到日志数据，请放心一些时间，它会在我们的批处理处理器中的计时器功能到期后自动发送日志。

有关 Apache APISIX 中 Batch-Processor 的更多信息，请参考：
[Batch-Processor](../batch-processor.md)

## 属性

| 属性名称          | 必选项  | 描述 |
|---------     |--------|-----------|
| host | 必要的 | TCP 服务的 IP 地址或主机名，请参考：[阿里云日志服务列表](https://help.aliyun.com/document_detail/29008.html?spm=a2c4g.11186623.2.14.49301b4793uX0z#reference-wgx-pwq-zdb)，建议配置 IP 取代配置域名。|
| port | 必要的 | 目标端口，阿里云日志服务默认端口为 10009。|
| timeout | 可选的 | 发送数据超时间。|
| log_format             | 可选的  | 日志格式以 JSON 的键值对声明。值支持字符串和嵌套对象（最多五层，超出部分将被截断）。字符串中可通过在前面加上 `$` 来引用 [APISIX 变量](../apisix-variable.md) 或 [NGINX 内置变量](http://nginx.org/en/docs/varindex.html)。 |
| project | 必要的 | 日志服务 Project 名称，请提前在阿里云日志服务中创建 Project。|
| logstore | 必须的 | 日志服务 Logstore 名称，请提前在阿里云日志服务中创建 Logstore。|
| access_key_id | 必须的 | AccessKey ID。建议使用阿里云子账号 AK，详情请参见 [授权](https://help.aliyun.com/document_detail/47664.html?spm=a2c4g.11186623.2.15.49301b47lfvxXP#task-xsk-ttc-ry)。|
| access_key_secret | 必须的 | AccessKey Secret。建议使用阿里云子账号 AK，详情请参见 [授权](https://help.aliyun.com/document_detail/47664.html?spm=a2c4g.11186623.2.15.49301b47lfvxXP#task-xsk-ttc-ry)。|
| include_req_body | 可选的 | 是否包含请求体。|
| include_req_body_expr   | 可选的 | 当 `include_req_body` 属性设置为 `true` 时的过滤器。只有当此处设置的表达式求值为 `true` 时，才会记录请求体。有关更多信息，请参阅 [lua-resty-expr](https://github.com/api7/lua-resty-expr) 。    |
| include_resp_body       | 可选的 | 当设置为 `true` 时，日志中将包含响应体。                                                     |
| include_resp_body_expr  | 可选的 | 当 `include_resp_body` 属性设置为 `true` 时进行过滤响应体，并且只有当此处设置的表达式计算结果为 `true` 时，才会记录响应体。更多信息，请参考 [lua-resty-expr](https://github.com/api7/lua-resty-expr)。 |
|name| 可选的 | 批处理名字。如果您使用 Prometheus 监视 APISIX 指标，名称将以 `apisix_batch_process_entries` 导出。|

注意：schema 中还定义了 `encrypt_fields = {"access_key_secret"}`，这意味着该字段将会被加密存储在 etcd 中。具体参考 [加密存储字段](../plugin-develop.md#加密存储字段)。

本插件支持使用批处理器来聚合并批量处理条目（日志/数据）。这样可以避免插件频繁地提交数据，默认设置情况下批处理器会每 `5` 秒钟或队列中的数据达到 `1000` 条时提交数据，如需了解或自定义批处理器相关参数设置，请参考 [Batch-Processor](../batch-processor.md#配置) 配置部分。

### 默认日志格式示例

```json
{
    "route_conf": {
        "host": "100.100.99.135",
        "buffer_duration": 60,
        "timeout": 30000,
        "include_req_body": false,
        "logstore": "your_logstore",
        "log_format": {
            "vip": "$remote_addr"
        },
        "project": "your_project",
        "inactive_timeout": 5,
        "access_key_id": "your_access_key_id",
        "access_key_secret": "your_access_key_secret",
        "batch_max_size": 1000,
        "max_retry_count": 0,
        "retry_delay": 1,
        "port": 10009,
        "name": "sls-logger"
    },
    "data": "<46>1 2024-01-06T03:29:56.457Z localhost apisix 28063 - [logservice project=\"your_project\" logstore=\"your_logstore\" access-key-id=\"your_access_key_id\" access-key-secret=\"your_access_key_secret\"] {\"vip\":\"127.0.0.1\",\"route_id\":\"1\"}\n"
}
```

## 插件元数据设置

| 名称             | 类型    | 必选项 | 默认值        | 有效值  | 描述                                             |
| ---------------- | ------- | ------ | ------------- | ------- | ------------------------------------------------ |
| log_format       | object  | 可选   |  |         | 日志格式以 JSON 的键值对声明。值支持字符串和嵌套对象（最多五层，超出部分将被截断）。字符串中可通过在前面加上 `$` 来引用 [APISIX 变量](../../../en/latest/apisix-variable.md) 或 [Nginx 内置变量](http://nginx.org/en/docs/varindex.html)。特别的，**该设置是全局生效的**，意味着指定 log_format 后，将对所有绑定 sls-logger 的 Route 或 Service 生效。 |

### 设置日志格式示例

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/sls-logger -H "X-API-KEY: $admin_key" -X PUT -d '
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

在日志收集处，将得到类似下面的日志：

```shell
{"host":"localhost","@timestamp":"2020-09-23T19:05:05-04:00","client_ip":"127.0.0.1","request":{"method":"GET","uri":"/hello"},"response":{"status":200},"route_id":"1"}
{"host":"localhost","@timestamp":"2020-09-23T19:05:05-04:00","client_ip":"127.0.0.1","request":{"method":"GET","uri":"/hello"},"response":{"status":200},"route_id":"1"}
```

## 如何开启

1. 下面例子展示了如何为指定路由开启 `sls-logger` 插件的。

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/5 -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "plugins": {
        "sls-logger": {
            "host": "100.100.99.135",
            "port": 10009,
            "project": "your_project",
            "logstore": "your_logstore",
            "access_key_id": "your_access_key_id",
            "access_key_secret": "your_access_key_secret",
            "timeout": 30000
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

```
注释：这里的 100.100.99.135 是阿里云华北 3 内外地址。
```

## 测试插件

* 成功的情况：

```shell
$ curl -i http://127.0.0.1:9080/hello
HTTP/1.1 200 OK
...
hello, world
```

* 查看阿里云日志服务上传记录
![sls logger view](../../../assets/images/plugin/sls-logger-1.png "阿里云日志服务预览")

## 删除插件

想要禁用“sls-logger”插件，是非常简单的，将对应的插件配置从 json 配置删除，就会立即生效，不需要重新启动服务：

```shell
$ curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
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
