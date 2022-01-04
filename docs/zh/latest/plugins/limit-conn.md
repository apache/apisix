---
title: limit-conn
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

限制并发请求（或并发连接）插件。

### 属性

| 名称               | 类型    | 必选项   | 默认值 | 有效值                                                                                    | 描述                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| ------------------ | ------- | -------- | ------ | ----------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| conn               | integer | required |        | conn > 0                                                                                  | 允许的最大并发请求数。超过 `conn` 的限制、但是低于 `conn` + `burst` 的请求，将被延迟处理。                                                                                                                                                                                                                                                                                                                                                    |
| burst              | integer | required |        | burst >= 0                                                                                | 允许被延迟处理的并发请求数。                                                                                                                                                                                                                                                                                                                                                                                                                  |
| default_conn_delay | number  | required |        | default_conn_delay > 0                                                                    | 默认的典型连接(或请求)的处理延迟时间。                                                                                                                                                                                                                                                                                                                                                                                                        |
| only_use_default_delay  | boolean | optional | false  | [true,false]                                                                              | 延迟时间的严格模式。 如果设置为`true`的话，将会严格按照设置的时间来进行延迟                                                                                                                                                                                                                                                                                                                                                                           |
| key_type      | string | 可选   |  "var"      | ["var", "var_combination"]                                          | key 的类型 |
| key           | string  | 必须   |        |  | 用来做请求计数的依据。如果 `key_type` 为 "var"，那么 key 会被当作变量名称，如 "remote_addr" 和 "consumer_name"。如果 `key_type` 为 "var_combination"，那么 key 会当作变量组合，如 "$remote_addr $consumer_name"。如果 key 的值为空，$remote_addr 会被作为默认 key。 |
| rejected_code      | string  | optional | 503    | [200,...,599]                                                                             | 当请求超过 `conn` + `burst` 这个阈值时，返回的 HTTP 状态码                                                                                                                                                                                                                                                                                                                                                                                    |
| rejected_msg       | string | 可选                                |            | 非空                                          | 当请求超过 `conn` + `burst` 这个阈值时，返回的响应体。                                                                                                                                                                                                             |
| allow_degradation              | boolean  | 可选                                | false       |                                                                     | 当插件功能临时不可用时是否允许请求继续。当值设置为 true 时则自动允许请求继续，默认值是 false。|

#### 如何启用

下面是一个示例，在指定的 route 上开启了 limit-conn 插件，并设置 `key_type` 为 `var`:

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/index.html",
    "id": 1,
    "plugins": {
        "limit-conn": {
            "conn": 1,
            "burst": 0,
            "default_conn_delay": 0.1,
            "rejected_code": 503,
            "key_type": "var",
            "key": "remote_addr"
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```

下面是一个示例，在指定的 route 上开启了 limit-conn 插件，并设置 `key_type` 为 `var_combination`:

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/index.html",
    "id": 1,
    "plugins": {
        "limit-conn": {
            "conn": 1,
            "burst": 0,
            "default_conn_delay": 0.1,
            "rejected_code": 503,
            "key_type": "var_combination",
            "key": "$consumer_name $remote_addr"
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```

你也可以通过 web 界面来完成上面的操作，先增加一个 route，然后在插件页面中添加 limit-conn 插件：
![enable limit-conn plugin](../../../assets/images/plugin/limit-conn-1.png)

#### test plugin

上面启用的插件的参数表示只允许一个并发请求。 当收到多个并发请求时，将直接返回 503 拒绝请求。

```shell
curl -i http://127.0.0.1:9080/index.html?sleep=20 &

curl -i http://127.0.0.1:9080/index.html?sleep=20
<html>
<head><title>503 Service Temporarily Unavailable</title></head>
<body>
<center><h1>503 Service Temporarily Unavailable</h1></center>
<hr><center>openresty</center>
</body>
</html>
```

这就表示 limit-conn 插件生效了。

#### 移除插件

当你想去掉 limit-conn 插件的时候，很简单，在插件的配置中把对应的 json 配置删除即可，无须重启服务，即刻生效：

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/index.html",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```

现在就已经移除了 limit-conn 插件了。其他插件的开启和移除也是同样的方法。
