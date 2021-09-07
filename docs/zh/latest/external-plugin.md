---
title: 外部插件
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

## 什么是外部插件和插件运行程序

APISIX 支持使用 Lua 语言写插件，这种类型的插件在 APISIX 内部执行。
有时候你想使用其他语言来开发插件，因此，APISIX 支持以边车的方式加载和运行你写的插件。
这里的边车就叫做插件运行程序，你写的插件叫做外部插件。

## 它是如何工作的

![external-plugin](../../assets/images/external-plugin.png)

当你在 APISIX 中配置了一个插件运行程序，APISIX 将以子进程的方式运行该插件运行程序。
该子进程与 APISIX 进程从属相同用户。当重启或者重新加载 APISIX 时，该插件运行程序也将被重启。

一旦你为指定路由配置了 `ext-plugin-*` 插件，
匹配该路由的请求将触发从 APISIX 到 插件运行程序的 RPC 调用。

插件运行程序将处理该 RPC 调用，在其侧创建一个请求，运行外部插件并将结果返回给 APISIX 。

外部插件及其执行顺序在这里 `ext-plugin-*` 配置。与其他插件一样，外部插件可以动态启用和重新配置。

## 支持的插件运行程序

- Java: https://github.com/apache/apisix-java-plugin-runner
- Go: https://github.com/apache/apisix-go-plugin-runner
- Python: https://github.com/apache/apisix-python-plugin-runner

## 在 APISIX 中配置插件运行程序

在生产环境运行插件运行程序，添加以下配置到 `config.yaml`：

```yaml
ext-plugin:
  cmd: ["blah"] # replace it to the real runner executable according to the runner you choice
```

APISIX 将以子进程的方式管理该插件运行程序。

注意：在 Mac 上，APISIX `v2.6` 无法管理该插件运行程序。

在开发过程中，我们希望单独运行插件运行程序，这样就可以重新启动它，而无需先重新启动 APISIX 。

通过指定环境变量 `APISIX_LISTEN_ADDRESS`, 我们可以使插件运行程序监听一个固定的地址。
例如：

```bash
APISIX_LISTEN_ADDRESS=unix:/tmp/x.sock ./the_runner
```

此时，插件运行程序将监听 `/tmp/x.sock`

同时，你需要配置 APISIX 发送 RPC 请求到该固定的地址：

```yaml
ext-plugin:
  # cmd: ["blah"] # don't configure the executable!
  path_for_test: "/tmp/x.sock" # without 'unix:' prefix
```

在生产环境，不应该使用 `path_for_test` 并且 unix socket 路径将动态生产。

## 常见问题

### 由 APISIX 管理时，插件运行程序无法访问我的环境变量

自`v2.7`，APISIX 可以将环境传递给插件运行程序。

然而，默认情况下，Nginx 将隐藏所有环境变量。所以你需要首先在 `conf/config.yaml` 中声明环境变量：

```yaml
nginx_config:
  envs:
    - MY_ENV_VAR
```

### APISIX 使用 SIGKILL 终止插件运行程序，而不是使用 SIGTERM！

自 `v2.7`，当跑在 OpenResty 1.19+ 时，APISIX 将使用 SIGTERM 来停止插件运行程序。

但是，APISIX 需要等待插件运行程序退出，这样我们才能确保资源得以被释放。

因此，我们先发送 SIGTERM 。然后在1秒后，如果插件运行程序仍然在运行，我们将发送 SIGKILL 。
