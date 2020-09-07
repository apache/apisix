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

- [English](../../plugins/log-rotate.md)

# log-rotate

本插件可自动完成 logs 目录下的 access 和 error 日志的定期切分。
通过配置参数可以设置每间隔多久切分一次日志，以及最近保留多少份日志（超过指定数量后，自动删除老文件）。

## 参数

|名称           |可选项  |说明|
|---------     |--------|-----------|
|interval      |必选    |每间隔多长时间切分一次日志，秒为单位，默认值为 3600秒 = 1 小时|
|max_kept      |必选    |最多保留多少份历史日志，超过指定数量后，自动删除老文件，默认值为 168 个。比如 `max_kept: 168` 代表 access 和 error 日志各自最多保留 168 份|

开启该插件后，就会按照参数自动切分日志文件了。比如下面的例子是根据 `interval: 10` 和 `max_kept: 10` 得到的样本。

```shell
$ ll logs
total 44K
-rw-r--r--. 1 resty resty    0 Mar 20 20:32 2020-03-20_20-32-40_access.log
-rw-r--r--. 1 resty resty 2.4K Mar 20 20:32 2020-03-20_20-32-40_error.log
-rw-r--r--. 1 resty resty    0 Mar 20 20:32 2020-03-20_20-32-50_access.log
-rw-r--r--. 1 resty resty 2.8K Mar 20 20:32 2020-03-20_20-32-50_error.log
-rw-r--r--. 1 resty resty    0 Mar 20 20:32 2020-03-20_20-33-00_access.log
-rw-r--r--. 1 resty resty 2.4K Mar 20 20:33 2020-03-20_20-33-00_error.log
-rw-r--r--. 1 resty resty    0 Mar 20 20:33 2020-03-20_20-33-10_access.log
-rw-r--r--. 1 resty resty 2.4K Mar 20 20:33 2020-03-20_20-33-10_error.log
-rw-r--r--. 1 resty resty    0 Mar 20 20:33 2020-03-20_20-33-20_access.log
-rw-r--r--. 1 resty resty 2.4K Mar 20 20:33 2020-03-20_20-33-20_error.log
-rw-r--r--. 1 resty resty    0 Mar 20 20:33 2020-03-20_20-33-30_access.log
-rw-r--r--. 1 resty resty 2.4K Mar 20 20:33 2020-03-20_20-33-30_error.log
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

### 示例

#### 开启插件

在 `conf/config.yaml` 中启用插件 `log-rotate` 即可，不需要在任何 route 或 service 中绑定。

```yaml
plugins:
    # the plugins you enabled
    - log-rotate

plugin_attr:
    log-rotate:
        interval: 3600    # rotate interval (unit: second)
        max_kept: 168     # max number of log files will be kept
```

#### 禁用插件

在 `conf/config.yaml` 中删除插件 `log-rotate` 即可。
