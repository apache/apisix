---
title: dubbo-proxy
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

## 描述

`dubbo-proxy` 插件允许将 `HTTP` 请求代理到 [**dubbo**](http://dubbo.apache.org)。

## 要求

如果你正在使用 `OpenResty`, 你需要编译它来支持 `dubbo`, 参考 [APISIX-Runtime](../FAQ.md#如何构建-apisix-runtime-环境)。

## 运行时属性

| 名称       | 类型 | 必选项 | 默认值  | 有效值       | 描述                                                          |
| ------------ | ------ | ----------- | -------- | ------------ | -------------------------------------------------------------------- |
| service_name    | string | 必选  |          |              | dubbo 服务名字 |
| service_version | string | 必选    |          |              | dubbo 服务版本 |
| method          | string | 可选    | uri 路径 |     | dubbo 服务方法 |

## 静态属性

| 名称       | 类型   | 必选项 | 默认值 | 有效值        | 描述                                                        |
| ------------ | ------ | ----------- | -------- | ------------ | -------------------------------------------------------------------- |
| upstream_multiplex_count | number | 必选    | 32        | >= 1 | 上游连接中最大的多路复用请求数 |

## 如何启用

首先，在 `config.yaml` 中启用 `dubbo-proxy` 插件：

```
# Add this in config.yaml
plugins:
  - ... # plugin you need
  - dubbo-proxy
```

然后重载 `APISIX`。

这里有个例子，在指定的路由中启用 `dubbo-proxy` 插件：

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/upstreams/1  -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "nodes": {
        "127.0.0.1:20880": 1
    },
    "type": "roundrobin"
}'

curl http://127.0.0.1:9180/apisix/admin/routes/1  -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uris": [
        "/hello"
    ],
    "plugins": {
        "dubbo-proxy": {
            "service_name": "org.apache.dubbo.sample.tengine.DemoService",
            "service_version": "0.0.0",
            "method": "tengineDubbo"
        }
    },
    "upstream_id": 1
}'
```

## 测试插件

你可以在 `Tengine` 提供的 [快速开始](https://github.com/alibaba/tengine/tree/master/modules/mod_dubbo#quick-start) 例子中使用上述配置进行测试。

将会有同样的结果。

从上游 `dubbo` 服务返回的数据一定是 `Map<String, String>` 类型。

如果返回的数据如下

```json
{
    "status": "200",
    "header1": "value1",
    "header2": "valu2",
    "body": "blahblah"
}
```

则对应的 `HTTP` 响应如下

```http
HTTP/1.1 200 OK # "status" will be the status code
...
header1: value1
header2: value2
...

blahblah # "body" will be the body
```

## 删除插件

当你想在某个路由或服务中禁用 `dubbo-proxy` 插件，非常简单，你可以直接删除插件配置中的 `json` 配置，不需要重启服务就能立即生效：

```shell
$ curl http://127.0.0.1:9180/apisix/admin/routes/1  -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "methods": ["GET"],
    "uris": [
        "/hello"
    ],
    "plugins": {
    },
    "upstream_id": 1
    }
}'
```

现在 `dubbo-proxy` 插件就已经被禁用了。此方法同样适用于其他插件。

如果你想彻底禁用 `dubbo-proxy` 插件，
你需要在 `config.yaml` 中注释掉以下内容：

```yaml
plugins:
  - ... # plugin you need
  #- dubbo-proxy
```

然后重新加载 `APISIX`。
