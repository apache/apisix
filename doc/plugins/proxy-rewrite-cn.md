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

[English](proxy-rewrite.md)
# proxy-rewrite

上游代理信息重写插件。

#### 配置参数
|名字    |可选|说明|
|-------         |-----|------|
|scheme          |可选| 转发到上游的新 `schema` 协议，可以是 `http` 或 `https`，默认 `http` 协议|
|uri             |可选| 转发到上游的新 `uri` 地址|
|host            |可选| 转发到上游的新 `host` 地址，例如：`iresty.com` |
|enable_websocket|可选| 是否启用 `websocket`（布尔值），默认不启用|
|headers         |可选| 转发到上游的新`headers`，可以设置多个。头信息如果存在将重写，不存在则添加。想要删除某个 header 的话，把对应的值设置为空字符串即可|

### 示例

#### 开启插件
下面是一个示例，在指定的 route 上开启了 `proxy rewrite` 插件:

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/test/index.html",
    "plugins": {
        "proxy-rewrite": {
            "uri": "/test/home.html",
            "scheme": "http",
            "host": "iresty.com",
            "enable_websocket": true,
            "headers": {
                "X-Api-Version": "v1",
                "X-Api-Engine": "apisix",
                "X-Api-useless": ""
            }
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:80": 1
        }
    }
}'
```

#### 测试插件
基于上述配置进行测试：
```shell
curl -X GET http://127.0.0.1:9080/test/index.html
```

发送请求，查看上游服务`access.log`，如果输出信息与配置一致：
```
127.0.0.1 - [26/Sep/2019:10:52:20 +0800] iresty.com GET /test/home.html HTTP/1.1 200 38 - curl/7.29.0 - 0.000 199 107
```

即表示 `proxy rewrite` 插件生效了。

#### 禁用插件
当你想去掉 `proxy rewrite` 插件的时候，很简单，在插件的配置中把对应的 json 配置删除即可，无须重启服务，即刻生效：

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/test/index.html",
    "plugins": {},
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:80": 1
        }
    }
}'
```

现在就已经移除了 `proxy rewrite` 插件了。其他插件的开启和移除也是同样的方法。
