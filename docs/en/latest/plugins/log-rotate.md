---
title: log-rotate
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - Log rotate
description: This document contains information about the Apache APISIX log-rotate Plugin.
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

## Description

The `log-rotate` Plugin is used to keep rotating access and error log files in the log directory at regular intervals.

You can configure how often the logs are rotated and how many logs to keep. When the number of logs exceeds, older logs are automatically deleted.

## Attributes

| Name               | Type    | Required | Default | Description                                                                                    |
|--------------------|---------|----------|---------|------------------------------------------------------------------------------------------------|
| interval           | integer | True     | 60 * 60 | Time in seconds specifying how often to rotate the logs.                                       |
| max_kept           | integer | True     | 24 * 7  | Maximum number of historical logs to keep. If this number is exceeded, older logs are deleted. |
| max_size           | integer | False    | -1      | Max size(Bytes) of log files to be rotated, size check would be skipped with a value less than 0 or time is up specified by interval. |
| enable_compression | boolean | False    | false   | When set to `true`, compresses the log file (gzip). Requires `tar` to be installed.            |

## Enable Plugin

To enable the Plugin, add it in your configuration file (`conf/config.yaml`):

```yaml title="conf/config.yaml"
plugins:
    - log-rotate

plugin_attr:
    log-rotate:
        interval: 3600    # rotate interval (unit: second)
        max_kept: 168     # max number of log files will be kept
        max_size: -1      # max size of log files will be kept
        enable_compression: false    # enable log file compression(gzip) or not, default false
```

## Example usage

Once you enable the Plugin as shown above, the logs will be stored and rotated based on your configuration.

In the example below the `interval` is set to `10` and `max_kept` is set to `10`. This will create logs as shown:

```shell
ll logs
```

```shell
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

If you have enabled compression, the logs will be as shown below:

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

## Delete Plugin

To remove the `log-rotate` Plugin, you can remove it from your configuration file (`conf/config.yaml`):

```yaml title="conf/config.yaml"
plugins:
    # - log-rotate
```
