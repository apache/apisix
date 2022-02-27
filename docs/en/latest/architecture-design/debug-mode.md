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

You can enable the basic debug mode by adding this line to your `conf/debug.yaml` file.

```
basic:
  enable: true
```

**Note**: Before Apache APISIX 2.10, basic debug mode was enabled by setting `apisix.enable_debug = true` in the `conf/config.yaml` file.

For example, if we are using two plugins `limit-conn` and `limit-count` for a Route `/hello`, we will receive a response with the header `Apisix-Plugins: limit-conn, limit-count` when we enable the basic debug mode.

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

If the debug information cannot be included in a response header (say when the plugin is in a stream subsystem), the information will be logged in the error log at a `warn` level.

### Advanced Debug Mode

Advanced debug mode can also be enabled by modifying the configuration in the `conf/debug.yaml` file.

Enable advanced debug mode by modifying the configuration in `conf/debug.yaml` file.

The checker checks every second for changes to the configuration files. An `#END` flag is added to let the checker know that it should only look for changes till that point.

The checker would only check this if the file was updated by checking its last modification time.

| Key                             | Optional | Description                                                                                                                               | Default |
| ------------------------------- | -------- | ----------------------------------------------------------------------------------------------------------------------------------------- | ------- |
| hook_conf.enable                | required | Enable/Disable hook debug trace. Target module function's input arguments or returned value would be printed once this option is enabled. | false   |
| hook_conf.name                  | required | The module list name of the hook which has enabled debug trace.                                                                               |         |
| hook_conf.log_level             | required | Logging levels for input arguments & returned values.                                                                                      | warn    |
| hook_conf.is_print_input_args   | required | Enable/Disable printing input arguments.                                                                                                     | true    |
| hook_conf.is_print_return_value | required | Enable/Disable printing returned values.                                                                                                      | true    |

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

### Enable Advanced Debug Mode Dynamically

You can also enable the advanced debug mode to take effect on particular requests.

For example, to dynamically enable advanced debugging mode on requests with a particular header name `X-APISIX-Dynamic-Debug` you can configure:

```yaml
http_filter:
  enable: true # Enable/Disable Advanced Debug Mode Dynamically
  enable_header_name: X-APISIX-Dynamic-Debug # Trace for the request with this header
......
#END
```

This will enable the advanced debug mode for requests like:

```shell
curl 127.0.0.1:9090/hello --header 'X-APISIX-Dynamic-Debug: foo'
```

**Note**: The `apisix.http_access_phase` module cannot be hooked for dynamic rules as the advanced debug mode is enabled based on the request.
