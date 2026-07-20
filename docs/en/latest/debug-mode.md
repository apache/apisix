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

If you have configured two Plugins `limit-conn` and `limit-count` on the Route `/hello`, you will receive a response with the header `Apisix-Plugins: limit-conn#access, limit-count#access, limit-conn#log` when you enable the basic debug mode. Each entry in the header is in the form `plugin-name#phase`, and the entries are listed in the runtime execution order of the plugin phase functions (for the phases running after the response header is generated, the expected execution order — see the note below).

```shell
curl http://127.0.0.1:1984/hello -i
```

```shell
HTTP/1.1 200 OK
Content-Type: text/plain
Transfer-Encoding: chunked
Connection: keep-alive
Apisix-Plugins: limit-conn#access, limit-count#access, limit-conn#log
X-RateLimit-Limit: 2
X-RateLimit-Remaining: 1
Server: openresty

hello world
```

:::info IMPORTANT

Restricted by the HTTP protocol, the phase functions executed after the response header is generated (such as `body_filter` and `log`) can not be traced into the response header at execution time. Instead, their entries are inferred right before the response header is generated: a matched plugin carrying such a phase function is reported as if it would execute it. The inferred entries may not fully reflect the real execution — for example, a plugin skipped at runtime by its `_meta.filter` is still reported.

The phase functions that can be neither traced nor inferred this way (for example, the ones of the plugins in global rules running after the response header is sent) are logged as an error log at a `warn` level instead, for example `Apisix-Plugins: response-rewrite#body_filter`.

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
