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

[English](basic-auth.md)

# 目录
- [**名字**](#名字)
- [**属性**](#属性)
- [**如何启用**](#如何启用)
- [**测试插件**](#测试插件)
- [**禁用插件**](#禁用插件)


## 名字

`basic-auth` 是一个认证插件，它需要与 `consumer` 一起配合才能工作。

添加 Basic Authentication 到一个 `service` 或 `route`。 然后 `consumer` 将其用户名和密码添加到请求头中以验证其请求。

有关 Basic Authentication 的更多信息，可参考 [维基百科](https://en.wikipedia.org/wiki/Basic_access_authentication) 查看更多信息。

## 属性

* `username`: 不同的 `consumer` 对象应有不同的值，它应当是唯一的。不同 consumer 使用了相同的 `username` ，将会出现请求匹配异常。
* `password`: 用户的密码

## 如何启用

1. 创建一个 consumer 对象，并设置插件 `basic-auth` 的值。

```shell
curl http://127.0.0.1:9080/apisix/admin/consumers -X PUT -d '
{
    "username": "foo",
    "plugins": {
        "basic-auth": {
            "username": "foo",
            "password": "bar"
        }
    }
}'
```
你可以使用浏览器打开 dashboard：`http://127.0.0.1:9080/apisix/dashboard/`，通过 web 界面来完成上面的操作，先增加一个 consumer：
![](../images/plugin/basic-auth-1.png)

然后在 consumer 页面中添加 basic-auth 插件：
![](../images/plugin/basic-auth-2.png)

2. 创建 Route 或 Service 对象，并开启 `basic-auth` 插件。

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/hello",
    "plugins": {
        "basic-auth": {}
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:8080": 1
        }
    }
}'
```

## Test Plugin


* 缺少 Authorization header

```shell
$ curl http://127.0.0.2:9080/hello -i
HTTP/1.1 401 Unauthorized
...
{"message":"Missing authorization in request"}
```

* 用户名不存在：

```shell
$ curl -i -ubar:bar http://127.0.0.1:9080/hello
HTTP/1.1 401 Unauthorized
...
{"message":"Invalid user key in authorization"}
```

* 密码错误：

```shell
$ curl -i -ufoo:foo http://127.0.0.1:9080/hello
HTTP/1.1 401 Unauthorized
...
{"message":"Password is error"}
...
```

* 成功请求：

```shell
$ curl -i -ufoo:bar http://127.0.0.1:9080/hello
HTTP/1.1 200 OK
...
hello, foo!
...
```


## 禁用插件

当你想去掉 `basic-auth` 插件的时候，很简单，在插件的配置中把对应的 `json` 配置删除即可，无须重启服务，即刻生效：

```shell
$ curl http://127.0.0.1:9080/apisix/admin/routes/1 -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/hello",
    "plugins": {},
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:8080": 1
        }
    }
}'
```
