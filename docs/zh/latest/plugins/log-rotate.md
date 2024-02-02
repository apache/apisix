---
title: log-rotate
keywords:
  - APISIX
  - API 网关
  - Plugin
  - 日志切分
description: 云原生 API 网关 Apache APISIX log-rotate 插件用于定期切分日志目录下的访问日志和错误日志。
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

`log-rotate` 插件用于定期切分日志目录下的访问日志和错误日志。

你可以自定义日志轮换的频率以及要保留的日志数量。当日志数量超过限制时，旧的日志会被自动删除。

## 参数

| 名称               | 类型     | 必选项 | 默认值  | 有效值        | 描述                                                                          |
| ------------------ | ------- | ------ | ------- | ------------- | ---------------------------------------------------------------------------- |
| interval           | integer | 是     | 60 * 60 |               | 每间隔多长时间切分一次日志，以秒为单位。                                        |
| max_kept           | integer | 是     | 24 * 7  |               | 最多保留多少份历史日志，超过指定数量后，自动删除老文件。                         |
| max_size           | integer | 否     | -1      |               | 日志文件超过指定大小时进行切分，单位为 Byte。如果 `max_size` 小于 0 或者根据 `interval` 计算的时间到达时，将不会根据 `max_size` 切分日志。 |
| enable_compression | boolean | 否     | false   | [false, true] | 当设置为 `true` 时，启用日志文件压缩。该功能需要在系统中安装 `tar` 。     |

开启该插件后，就会按照参数自动切分日志文件了。比如以下示例是根据 `interval: 10` 和 `max_kept: 10` 得到的样本。

```shell
ll logs
```

```
total 44K
-rw-r--r--. 1 resty resty    0 Mar 20 20:33 2020-03-20_20-33-40_access.log
-rw-r--r--. 1 resty resty 2.8K Mar 20 20:33 2020-03-20_20-33-40_error.log
-rw-r--r--. 1 resty resty    0 Mar 20 20:33 2020-03-20_20-33-50_access.log
-rw-r--r--. 1 resty resty 2.4K Mar 20 20:33 2020-03-20_20-33-50_error.log
-rw-r--r--. 1 resty resty    0 Mar 20 20:33 2020-03-20_20-34-00_access.log
-rw-r--r--. 1 resty resty 2.4K Mar 20 20:34 2020-03-20_20-34-00_error.log
-rw-r--r--. 1 resty resty    0 Mar 20 20:34 2020-03-20_20-34-10_access.log
-rw-r--r--. 1 resty resty 2.4K Mar 20 20:34 2020-03-20_20-34-10_error.log
-rw-r--r--. 1 resty resty    0 Mar 20 20:34 access.log
-rw-r--r--. 1 resty resty 1.5K Mar 20 21:31 error.log
```

当开启日志文件压缩时，日志文件名称如下所示：

```shell
ll logs
```

```shell
total 10.5K
-rw-r--r--. 1 resty resty  1.5K Mar 20 20:33 2020-03-20_20-33-50_access.log.tar.gz
-rw-r--r--. 1 resty resty  1.5K Mar 20 20:33 2020-03-20_20-33-50_error.log.tar.gz
-rw-r--r--. 1 resty resty  1.5K Mar 20 20:33 2020-03-20_20-34-00_access.log.tar.gz
-rw-r--r--. 1 resty resty  1.5K Mar 20 20:34 2020-03-20_20-34-00_error.log.tar.gz
-rw-r--r--. 1 resty resty  1.5K Mar 20 20:34 2020-03-20_20-34-10_access.log.tar.gz
-rw-r--r--. 1 resty resty  1.5K Mar 20 20:34 2020-03-20_20-34-10_error.log.tar.gz
-rw-r--r--. 1 resty resty    0 Mar 20 20:34 access.log
-rw-r--r--. 1 resty resty 1.5K Mar 20 21:31 error.log
```

## 启用插件

**该插件默认为禁用状态**，你可以在 `./conf/config.yaml` 中启用 `log-rotate` 插件，不需要在任何路由或服务中绑定。

```yaml title="./conf/config.yaml"
plugins:
    # the plugins you enabled
    - log-rotate

plugin_attr:
    log-rotate:
        interval: 3600    # rotate interval (unit: second)
        max_kept: 168     # max number of log files will be kept
        max_size: -1      # max size of log files will be kept
        enable_compression: false    # enable log file compression(gzip) or not, default false
```

配置完成，你需要重新加载 APISIX。

## 删除插件

当你不再需要该插件时，只需要在 `./conf/config.yaml` 中删除或注释该插件即可。

```yaml
plugins:
    # the plugins you enabled
    # - log-rotate

plugin_attr:

```
