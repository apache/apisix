---
title: Debug Mode
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

### Basic Debug Mode

Enable basic debug mode just by setting `apisix.enable_debug = true` in `conf/config.yaml` file.

e.g Using both `limit-conn` and `limit-count` plugins for a `/hello` request, there will have a response header called `Apisix-Plugins: limit-conn, limit-count`.

```shell
$ curl http://127.0.0.1:1984/hello -i
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

If the information can be delivered via HTTP response header, for example, the plugin is in stream
subsystem, the information will be logged in the error log with `warn` level.

### Advanced Debug Mode

Enable advanced debug mode by modifying the configuration in `conf/debug.yaml` file. Because there will be a check every second, only the checker reads the `#END` flag, and the file would be considered as closed.

The checker would judge whether the file data changed according to the last modification time of the file. If there has any change, reload it. If there was no change, skip this check. So it's hot reload for enabling or disabling advanced debug mode.

| Key                             | Optional | Description                                                                                                                               | Default |
| ------------------------------- | -------- | ----------------------------------------------------------------------------------------------------------------------------------------- | ------- |
| hook_conf.enable                | required | Enable/Disable hook debug trace. Target module function's input arguments or returned value would be printed once this option is enabled. | false   |
| hook_conf.name                  | required | The module list name of hook which has enabled debug trace.                                                                               |         |
| hook_conf.log_level             | required | Logging levels for input arguments & returned value.                                                                                      | warn    |
| hook_conf.is_print_input_args   | required | Enable/Disable input arguments print.                                                                                                     | true    |
| hook_conf.is_print_return_value | required | Enable/Disable returned value print.                                                                                                      | true    |

Example:

```yaml
hook_conf:
  enable: false # Enable/Disable Hook Debug Trace
  name: hook_phase # The Module List Name of Hook which has enabled Debug Trace
  log_level: warn # Logging Levels
  is_print_input_args: true # Enable/Disable Input Arguments Print
  is_print_return_value: true # Enable/Disable Returned Value Print

hook_phase: # Module Function List, Name: hook_phase
  apisix: # Referenced Module Name
    - http_access_phase # Function Names：Array
    - http_header_filter_phase
    - http_body_filter_phase
    - http_log_phase
#END
```
