---
title: APISIX
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

## 插件加载流程

![插件加载流程](../../../assets/images/flow-load-plugin.png)

## 插件内部结构

![插件内部结构](../../../assets/images/flow-plugin-internal.png)

## 配置 APISIX

通过修改本地 `conf/config.yaml` 文件，或者在启动 APISIX 时使用 `-c` 或 `--config` 添加文件路径参数 `apisix start -c <path string>`，完成对 APISIX 服务本身的基本配置。

比如修改 APISIX 默认监听端口为 8000，其他配置保持默认，在 `config.yaml` 中只需这样配置：

```yaml
apisix:
  node_listen: 8000 # APISIX listening port
```

比如指定 APISIX 默认监听端口为 8000，并且设置 etcd 地址为 `http://foo:2379`，
其他配置保持默认。在 `config.yaml` 中只需这样配置：

```yaml
apisix:
  node_listen: 8000 # APISIX listening port

etcd:
  host: "http://foo:2379" # etcd address
```

其他默认配置，可以在 `conf/config-default.yaml` 文件中看到，该文件是与 APISIX 源码强绑定，
**永远不要**手工修改 `conf/config-default.yaml` 文件。如果需要自定义任何配置，都应在 `config.yaml` 文件中完成。

_注意_ 不要手工修改 APISIX 自身的 `conf/nginx.conf` 文件，当服务每次启动时，`apisix`
会根据 `config.yaml` 配置自动生成新的 `conf/nginx.conf` 并自动启动服务。
