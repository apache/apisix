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

### 基本调试模式

设置 `conf/config.yaml` 中的 `apisix.enable_debug` 为 `true`，即可开启基本调试模式。

比如对 `/hello` 开启了 `limit-conn`和`limit-count`插件，这时候应答头中会有 `Apisix-Plugins: limit-conn, limit-count`。

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

如果这个信息无法通过 HTTP 应答头传递，比如插件在 stream 子系统里面执行，
那么这个信息会以 warn 等级日志写入到错误日志中。

### 高级调试模式

设置 `conf/debug.yaml` 中的选项，开启高级调试模式。由于 APISIX 服务启动后是每秒定期检查该文件，
当可以正常读取到 `#END` 结尾时，才认为文件处于写完关闭状态。

根据文件最后修改时间判断文件内容是否有变化，如有变化则重新加载，如没变化则跳过本次检查。
所以高级调试模式的开启、关闭都是热更新方式完成。

| 名字                            | 可选项 | 说明                                                               | 默认值 |
| ------------------------------- | ------ | ------------------------------------------------------------------ | ------ |
| hook_conf.enable                | 必选项 | 是否开启 hook 追踪调试。开启后将打印指定模块方法的请求参数或返回值 | false  |
| hook_conf.name                  | 必选项 | 开启 hook 追踪调试的模块列表名称                                   |        |
| hook_conf.log_level             | 必选项 | 打印请求参数和返回值的日志级别                                     | warn   |
| hook_conf.is_print_input_args   | 必选项 | 是否打印输入参数                                                   | true   |
| hook_conf.is_print_return_value | 必选项 | 是否打印返回值                                                     | true   |

请看下面示例：

```yaml
hook_conf:
  enable: false # 是否开启 hook 追踪调试
  name: hook_phase # 开启 hook 追踪调试的模块列表名称
  log_level: warn # 日志级别
  is_print_input_args: true # 是否打印输入参数
  is_print_return_value: true # 是否打印返回值

hook_phase: # 模块函数列表，名字：hook_phase
  apisix: # 引用的模块名称
    - http_access_phase # 函数名：数组
    - http_header_filter_phase
    - http_body_filter_phase
    - http_log_phase
#END
```
