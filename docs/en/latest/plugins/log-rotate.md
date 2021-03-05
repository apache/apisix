---
title: log-rotate
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

## Name

The plug-in can automatically rotate access and error log files in the log directory at regular intervals.

Specify how often logs are rotated every interval and how many logs have been kept recently.
When the number of log files exceeds the remaining number, the old files are automatically deleted.

## Attributes

| Name     | Type    | Requirement | Default | Valid | Description                                                                                                          |
| -------- | ------- | ----------- | ------- | ----- | -------------------------------------------------------------------------------------------------------------------- |
| interval | integer | required    | 60 * 60 |       | How often to rotate the log in seconds                                                                               |
| max_kept | integer | required    | 24 * 7  |       | How many historical logs can be kept at most. When this number is exceeded, old files will be deleted automatically. |

After this plug-in is enabled, the log file will be automatically rotated according to the configuration.
For example, the following example is a sample based on `interval: 10` and `max_kept: 10`.

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

### Example

#### Enable plugin

Enable the plug-in `log-rotate` in `conf/config.yaml`, then this plugin can work fine.
It does not need to be bound in any route or service.

Here is an example of `conf/config.yaml`:

```yaml
plugins:
    # the plugins you enabled
    - log-rotate

plugin_attr:
    log-rotate:
        interval: 3600    # rotate interval (unit: second)
        max_kept: 168     # max number of log files will be kept
```

#### Disable plugin

Remove the plugin `log-rotate` from `conf/config.yaml`.
