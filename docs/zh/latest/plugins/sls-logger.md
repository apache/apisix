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

## 摘要

- [**定义**](#定义)
- [**属性列表**](#属性列表)
- [**如何开启**](#如何开启)
- [**测试插件**](#测试插件)
- [**禁用插件**](#禁用插件)

## 定义

`sls-logger` 是使用[RF5424](https://tools.ietf.org/html/rfc5424)标准将日志数据以JSON格式发送到[阿里云日志服务](https://help.aliyun.com/document_detail/112903.html?spm=a2c4g.11186623.6.763.21321b47wcwt1u)。

该插件提供了将Log Data作为批处理推送到阿里云日志服务器的功能。如果您没有收到日志数据，请放心一些时间，它会在我们的批处理处理器中的计时器功能到期后自动发送日志。

有关Apache APISIX中Batch-Processor的更多信息，请参考：
[Batch-Processor](../batch-processor.md)

## 属性列表

|属性名称          |必选项  |描述|
|---------     |--------|-----------|
| host |必要的| TCP 服务的IP地址或主机名，请参考：[阿里云日志服务列表](https://help.aliyun.com/document_detail/29008.html?spm=a2c4g.11186623.2.14.49301b4793uX0z#reference-wgx-pwq-zdb)，建议配置 IP 取代配置域名。|
| port |必要的| 目标端口，阿里云日志服务默认端口为 10009。|
| timeout |可选的|发送数据超时间。|
| project |必要的|日志服务Project名称，请提前在阿里云日志服务中创建 Project。|
| logstore | 必须的 |日志服务Logstore名称，请提前在阿里云日志服务中创建  Logstore。|
| access_key_id | 必须的 | AccessKey ID。建议使用阿里云子账号AK，详情请参见[授权](https://help.aliyun.com/document_detail/47664.html?spm=a2c4g.11186623.2.15.49301b47lfvxXP#task-xsk-ttc-ry)。|
| access_key_secret | 必须的 | AccessKey Secret。建议使用阿里云子账号AK，详情请参见[授权](https://help.aliyun.com/document_detail/47664.html?spm=a2c4g.11186623.2.15.49301b47lfvxXP#task-xsk-ttc-ry)。|
| include_req_body | 可选的| 是否包含请求体。|
|name| 可选的|批处理名字。|
|batch_max_size |可选的       |每批的最大大小。|
|inactive_timeout|可选的      |如果不活动，将刷新缓冲区的最大时间（以秒为单位）。|
|buffer_duration|可选的       |必须先处理批次中最旧条目的最大期限（以秒为单位）。|
|max_retry_count|可选的       |从处理管道中移除之前的最大重试次数。|
|retry_delay    |可选的       |如果执行失败，应该延迟进程执行的秒数。|

## 如何开启

1. 下面例子展示了如何为指定路由开启 `sls-logger` 插件的。

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/5 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
注释:这里的 100.100.99.135 是阿里云华北3内外地址。
```

## 测试插件

* 成功的情况:

```shell
$ curl -i http://127.0.0.1:9080/hello
HTTP/1.1 200 OK
...
hello, world
```

* 查看阿里云日志服务上传记录
![](../../../assets/images/plugin/sls-logger-1.png "阿里云日志服务预览")

## 禁用插件

想要禁用“sls-logger”插件，是非常简单的，将对应的插件配置从json配置删除，就会立即生效，不需要重新启动服务：

```shell
$ curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d value='
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
