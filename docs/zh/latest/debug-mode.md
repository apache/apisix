---
title: 调试模式
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

设置 `conf/debug.yaml` 即可开启基本调试模式：

```
basic:
  enable: true
#END
```

注意：在 APISIX 2.10 之前，开启基本调试模式曾经是设置 `conf/config.yaml` 中的 `apisix.enable_debug` 为 `true`。

比如对 `/hello` 开启了 `limit-conn` 和 `limit-count` 插件，这时候应答头中会有 `Apisix-Plugins: limit-conn#access, limit-count#access, limit-conn#log`。
应答头中的每一项都是 `插件名#执行阶段` 的形式，并且严格按照插件阶段函数在运行时的执行顺序排列。

```shell
$ curl http://127.0.0.1:1984/hello -i
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

受限于 HTTP 协议，在应答头生成之后才执行的插件阶段函数（如 `body_filter`、`log`）无法在执行时
被记录到应答头中。应答头中的这类条目是在应答头生成前**推算**出来的：只要匹配到的插件带有对应的
阶段函数，就会被记录。因此这些条目不完全代表真实的执行情况——例如某插件在运行时被 `_meta.filter`
跳过，它仍会出现在应答头中。

无法通过执行记录或推算体现的阶段函数（例如 global rule 中的插件在应答头发送之后执行的阶段），
会以 warn 等级日志写入到错误日志中，例如 `Apisix-Plugins: response-rewrite#body_filter`。

### 高级调试模式

设置 `conf/debug.yaml` 中的选项，开启高级调试模式。由于 APISIX 服务启动后是每秒定期检查该文件，
当可以正常读取到 `#END` 结尾时，才认为文件处于写完关闭状态。

根据文件最后修改时间判断文件内容是否有变化，如有变化则重新加载，如没变化则跳过本次检查。
所以高级调试模式的开启、关闭都是热更新方式完成。

| 名称                             | 必选项 | 说明                                                          | 默认值 |
| ------------------------------- | ------ | ------------------------------------------------------------- | ------ |
| hook_conf.enable                | 是     | 是否开启 hook 追踪调试。开启后将打印指定模块方法的请求参数或返回值。 | false  |
| hook_conf.name                  | 是     | 开启 hook 追踪调试的模块列表名称。                               |        |
| hook_conf.log_level             | 是     | 打印请求参数和返回值的日志级别。                                  | warn   |
| hook_conf.is_print_input_args   | 是     | 是否打印输入参数。                                              | true   |
| hook_conf.is_print_return_value | 是     | 是否打印返回值。                                                | true   |

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

### 动态高级调试模式

动态高级调试模式是基于高级调试模式，可以由单个请求动态开启高级调试模式。设置 `conf/debug.yaml` 中的选项。

示例：

```yaml
http_filter:
  enable: true # 是否动态开启高级调试模式
  enable_header_name: X-APISIX-Dynamic-Debug # 追踪携带此 header 的请求
......
#END
```

动态开启高级调试模式，示例：

```shell
curl 127.0.0.1:9090/hello --header 'X-APISIX-Dynamic-Debug: foo'
```

注意：动态高级调试模式无法调试 `apisix.http_access_phase`，模块（因为请求进入 `apisix.http_access_phase` 模块后，才会判断是否动态开启高级调试模式）。
