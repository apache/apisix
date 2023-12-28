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
| log_format             | 可选的  | 以 JSON 格式的键值对来声明日志格式。对于值部分，仅支持字符串。如果是以 `$` 开头，则表明是要获取 [APISIX 变量](../apisix-variable.md) 或 [NGINX 内置变量](http://nginx.org/en/docs/varindex.html)。 |
| project | 必要的 | 日志服务 Project 名称，请提前在阿里云日志服务中创建 Project。|
| logstore | 必须的 | 日志服务 Logstore 名称，请提前在阿里云日志服务中创建 Logstore。|
| access_key_id | 必须的 | AccessKey ID。建议使用阿里云子账号 AK，详情请参见 [授权](https://help.aliyun.com/document_detail/47664.html?spm=a2c4g.11186623.2.15.49301b47lfvxXP#task-xsk-ttc-ry)。|
| access_key_secret | 必须的 | AccessKey Secret。建议使用阿里云子账号 AK，详情请参见 [授权](https://help.aliyun.com/document_detail/47664.html?spm=a2c4g.11186623.2.15.49301b47lfvxXP#task-xsk-ttc-ry)。|
| include_req_body | 可选的 | 是否包含请求体。|
|name| 可选的 | 批处理名字。如果您使用 Prometheus 监视 APISIX 指标，名称将以 `apisix_batch_process_entries` 导出。|

注意：schema 中还定义了 `encrypt_fields = {"access_key_secret"}`，这意味着该字段将会被加密存储在 etcd 中。具体参考 [加密存储字段](../plugin-develop.md#加密存储字段)。

本插件支持使用批处理器来聚合并批量处理条目（日志/数据）。这样可以避免插件频繁地提交数据，默认设置情况下批处理器会每 `5` 秒钟或队列中的数据达到 `1000` 条时提交数据，如需了解或自定义批处理器相关参数设置，请参考 [Batch-Processor](../batch-processor.md#配置) 配置部分。

## 插件元数据设置

| 名称             | 类型    | 必选项 | 默认值        | 有效值  | 描述                                             |
| ---------------- | ------- | ------ | ------------- | ------- | ------------------------------------------------ |
| log_format       | object  | 可选   |  |         | 以 JSON 格式的键值对来声明日志格式。对于值部分，仅支持字符串。如果是以 `$` 开头，则表明是要获取 [APISIX 变量](../../../en/latest/apisix-variable.md) 或 [Nginx 内置变量](http://nginx.org/en/docs/varindex.html)。特别的，**该设置是全局生效的**，意味着指定 log_format 后，将对所有绑定 sls-logger 的 Route 或 Service 生效。 |

### 设置日志格式示例

```shell
curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/sls-logger -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "log_format": {
        "host": "$host",
        "@timestamp": "$time_iso8601",
        "client_ip": "$remote_addr"
    }
}'
```

在日志收集处，将得到类似下面的日志：

```shell
{"host":"localhost","@timestamp":"2020-09-23T19:05:05-04:00","client_ip":"127.0.0.1","route_id":"1"}
{"host":"localhost","@timestamp":"2020-09-23T19:05:05-04:00","client_ip":"127.0.0.1","route_id":"1"}
```

## 如何开启

1. 下面例子展示了如何为指定路由开启 `sls-logger` 插件的。

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/5 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
$ curl http://127.0.0.1:9180/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
