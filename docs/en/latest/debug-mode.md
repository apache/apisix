---
id: debug-mode
title: Debug mode
keywords:
  - API gateway
  - Apache APISIX
  - Debug mode
description: Guide for enabling debug mode in Apache APISIX.
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

You can use APISIX's debug mode to troubleshoot your configuration.

## Basic debug mode

You can enable the basic debug mode by adding this line to your debug configuration file (`conf/debug.yaml`):

```yaml title="conf/debug.yaml"
basic:
  enable: true
#END
```

APISIX loads the configurations of `debug.yaml` on startup and then checks if the file is modified on an interval of 1 second. If the file is changed, APISIX automatically applies the configuration changes.

:::note

For APISIX releases prior to v2.10, basic debug mode is enabled by setting `apisix.enable_debug = true` in your configuration file (`conf/config.yaml`).

:::

If you have configured two Plugins `limit-conn` and `limit-count` on the Route `/hello`, you will receive a response with the header `Apisix-Plugins: limit-conn, limit-count` when you enable the basic debug mode.

```shell
curl http://127.0.0.1:1984/hello -i
```

```shell
HTTP/1.1 200 OK
Content-Type: text/plain
Transfer-Encoding: chunked
Connection: keep-alive
Apisix-Plugins: limit-conn, limit-count
X-RateLimit-Limit: 2
X-RateLimit-Remaining: 1
Server: openresty

hello world
```

:::info IMPORTANT

If the debug information cannot be included in a response header (for example, when the Plugin is in a stream subsystem), the debug information will be logged as an error log at a `warn` level.

:::

## Advanced debug mode

You can configure advanced options in debug mode by modifying your debug configuration file (`conf/debug.yaml`).

The following configurations are available:

| Key                             | Required | Default | Description                                                                                                           |
|---------------------------------|----------|---------|-----------------------------------------------------------------------------------------------------------------------|
| hook_conf.enable                | True     | false   | Enables/disables hook debug trace. i.e. if enabled, will print the target module function's inputs or returned value. |
| hook_conf.name                  | True     |         | Module list name of the hook that enabled the debug trace.                                                            |
| hook_conf.log_level             | True     | warn    | Log level for input arguments & returned values.                                                                      |
| hook_conf.is_print_input_args   | True     | true    | When set to `true` enables printing input arguments.                                                                  |
| hook_conf.is_print_return_value | True     | true    | When set to `true` enables printing returned values.                                                                  |

:::note

A checker would check every second for changes to the configuration file. It will only check a file if the file was updated based on its last modification time.

You can add an `#END` flag to indicate to the checker to only look for changes until that point.

:::

The example below shows how you can configure advanced options in debug mode:

```yaml title="conf/debug.yaml"
hook_conf:
  enable: false # Enables/disables hook debug trace
  name: hook_phase # Module list name of the hook that enabled the debug trace
  log_level: warn # Log level for input arguments & returned values
  is_print_input_args: true # When set to `true` enables printing input arguments
  is_print_return_value: true # When set to `true` enables printing returned values

hook_phase: # Module function list, Name: hook_phase
  apisix: # Referenced module name
    - http_access_phase # Function names：Array
    - http_header_filter_phase
    - http_body_filter_phase
    - http_log_phase
#END
```

### Dynamically enable advanced debug mode

You can also enable advanced debug mode only on particular requests.

The example below shows how you can enable it on requests with the header `X-APISIX-Dynamic-Debug`:

```yaml title="conf/debug.yaml"
http_filter:
  enable: true # Enable/disable advanced debug mode dynamically
  enable_header_name: X-APISIX-Dynamic-Debug # Trace for the request with this header
...
#END
```

This will enable the advanced debug mode only for requests like:

```shell
curl 127.0.0.1:9090/hello --header 'X-APISIX-Dynamic-Debug: foo'
```

:::note

The `apisix.http_access_phase` module cannot be hooked for this dynamic rule as the advanced debug mode is enabled based on the request.

:::
