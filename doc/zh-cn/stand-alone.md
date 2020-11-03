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

[English](../stand-alone.md)

## Stand-alone mode

开启 Stand-alone 模式的 APISIX 节点，将不再使用默认的 etcd 作为配置中心。

这种方式比较适合两类用户：

1. kubernetes(k8s)：声明式 API 场景，通过全量 yaml 配置来动态更新修改路由规则。
2. 不同配置中心：配置中心的实现有很多，比如 Consul 等，使用全量 yaml 做中间转换桥梁。

APISIX 节点服务启动后会立刻加载 `conf/apisix.yaml` 文件中的路由规则到内存，并且每间隔一定时间
（默认 1 秒钟），都会尝试检测文件内容是否有更新，如果有更新则重新加载规则。

*注意*：重新加载规则并更新时，均是内存热更新，不会有工作进程的替换过程，是个热更新过程。

通过设置 `conf/config.yaml` 中的 `apisix.config_center` 选项为 `yaml` 表示启
用 Stand-alone 模式。

参考下面示例：

```yaml
apisix:
  # ...
  config_center: yaml             # etcd: use etcd to store the config value
                                  # yaml: fetch the config value from local yaml file `/your_path/conf/apisix.yaml`
# ...
```

此外由于目前 Admin API 都是基于 etcd 配置中心解决方案，当开启 Stand-alone 模式后，
Admin API 实际将不起作用。

## 如何配置规则

所有的路由规则均存放在 `conf/apisix.yaml` 这一个文件中，APISIX 会以每秒（默认）频率检查文件是否有变化，如果有变化，则会检查文件末尾是否能找到 `#END` 结尾，找到后则重新加载文件更新到内存。

下面就是个最小的示例：

```yaml
routes:
  -
    uri: /hello
    upstream:
        nodes:
            "127.0.0.1:1980": 1
        type: roundrobin
#END
```

*注意*：如果`conf/apisix.yaml`末尾不能找到 `#END`，那么 APISIX 将不会加载这个文件规则到内存。

### 配置 Router

单个 Router：

```yaml
routes:
  -
    uri: /hello
    upstream:
        nodes:
            "127.0.0.1:1980": 1
        type: roundrobin
#END
```

多个 Router：

```yaml
routes:
  -
    uri: /hello
    upstream:
        nodes:
            "127.0.0.1:1980": 1
        type: roundrobin
  -
    uri: /hello2
    upstream:
        nodes:
            "127.0.0.1:1981": 1
        type: roundrobin
#END
```

### 配置 Router + Service

```yml
routes:
    -
        uri: /hello
        service_id: 1
services:
    -
        id: 1
        upstream:
            nodes:
                "127.0.0.1:1980": 1
            type: roundrobin
#END
```

### 配置 Router + Upstream

```yml
routes:
    -
        uri: /hello
        upstream_id: 1
upstreams:
    -
        id: 1
        nodes:
            "127.0.0.1:1980": 1
        type: roundrobin
#END
```

#### 配置 Router + Service + Upstream

```yml
routes:
    -
        uri: /hello
        service_id: 1
services:
    -
        id: 1
        upstream_id: 2
upstreams:
    -
        id: 2
        nodes:
            "127.0.0.1:1980": 1
        type: roundrobin
#END
```

#### 配置 Plugins

```yml
# 列出的插件会被热加载并覆盖掉启动时的配置
plugins:
  - name: ip-restriction
  - name: jwt-auth
  - name: mqtt-proxy
    stream: true # stream 插件需要设置 stream 属性为 true
```
