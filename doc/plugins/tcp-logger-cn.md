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

# 摘要
- [**定义**](#name)
- [**属性列表**](#attributes)
- [**如何开启**](#how-to-enable)
- [**测试插件**](#test-plugin)
- [**禁用插件**](#disable-plugin)


## 定义

`tcp-logger` 是用于将日志数据发送到TCP服务的插件。

以实现将日志数据以JSON格式发送到监控工具或其它TCP服务的能力。

## 属性列表

|属性名称          |必选项  |描述|
|---------     |--------|-----------|
| host |必要的| TCP 服务的IP地址或主机名。|
| port |必要的| 目标端口。|
| timeout |可选的|发送数据超时间。|
| tls |可选的|布尔值，用于控制是否执行SSL验证。|
| tls_options |可选的|TLS 选项|


## 如何开启

1. 下面例子展示了如何为指定路由开启 `tcp-logger` 插件的。

```shell
curl http://127.0.0.1:9080/apisix/admin/consumers -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "username": "foo",
    "plugins": {
          "plugins": {
                "tcp-logger": {
                     "host": "127.0.0.1",
                     "port": 5044,
                     "tls": false
                }
           },
          "upstream": {
               "type": "roundrobin",
               "nodes": {
                   "127.0.0.1:1980": 1
               }
          },
          "uri": "/hello"
    }
}'
```

## 测试插件

* 成功的情况:

```shell
$ curl -i http://127.0.0.1:9080/hello
HTTP/1.1 200 OK
...
hello, world
```

## 禁用插件


想要禁用“tcp-logger”插件，是非常简单的，将对应的插件配置从json配置删除，就会立即生效，不需要重新启动服务：

```shell
$ curl http://127.0.0.1:2379/apisix/admin/routes/1 -X PUT -d value='
{
    "methods": ["GET"],
    "uri": "/hello",
    "plugins": {},
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```
