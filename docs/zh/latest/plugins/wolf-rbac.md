---
title: wolf-rbac
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - wolf RBAC
  - wolf-rbac
description: 本文介绍了关于 Apache APISIX `wolf-rbac` 插件的基本信息及使用方法。
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

`wolf-rbac` 插件为 [role-based access control](https://en.wikipedia.org/wiki/Role-based_access_control) 系统提供了添加 [wolf](https://github.com/iGeeky/wolf) 到 Route 或 Service 的功能。此插件需要与 [Consumer](../terminology/consumer.md) 一起使用。

## 属性

| 名称          | 类型   | 必选项  | 默认值                    | 描述                                                                                                                                               |
| ------------- | ------ | ------ | ------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| server        | string | 否     | "http://127.0.0.1:12180" |  `wolf-server` 的服务地址。                                                                                                                          |
| appid         | string | 否     | "unset"                  | 在 `wolf-console` 中已经添加的应用 id。该字段支持使用 [APISIX Secret](../terminology/secret.md) 资源，将值保存在 Secret Manager 中。                                       |
| header_prefix | string | 否     | "X-"                     | 自定义 HTTP 头的前缀。`wolf-rbac` 在鉴权成功后，会在请求头 (用于传给后端) 及响应头 (用于传给前端) 中添加 3 个 header：`X-UserId`, `X-Username`, `X-Nickname`。|

## 接口

该插件在启用时将会增加以下接口：

* /apisix/plugin/wolf-rbac/login
* /apisix/plugin/wolf-rbac/change_pwd
* /apisix/plugin/wolf-rbac/user_info

:::note

以上接口需要通过 [public-api](../../../en/latest/plugins/public-api.md) 插件暴露。

:::

## 前提条件

如果要使用这个插件，你必须要[安装 wolf](https://github.com/iGeeky/wolf/blob/master/quick-start-with-docker/README.md) 并启动它。

完成后，你需要添加`application`、`admin`、`regular user`、`permission`、`resource` 等字段，并将用户授权到 [wolf-console](https://github.com/iGeeky/wolf/blob/master/docs/usage.md)。

## 启用插件

首先需要创建一个 Consumer 并配置该插件，如下所示：

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/consumers  \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
  "username":"wolf_rbac",
  "plugins":{
    "wolf-rbac":{
      "server":"http://127.0.0.1:12180",
      "appid":"restful"
    }
  },
  "desc":"wolf-rbac"
}'
```

:::note

示例中填写的 `appid`，必须是已经在 wolf 控制台中存在的。

:::

然后你需要添加 `wolf-rbac` 插件到 Route 或 Service 中。

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/*",
    "plugins": {
        "wolf-rbac": {}
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "www.baidu.com:80": 1
        }
    }
}'
```

你还可以通过 [APISIX Dashboard](https://github.com/apache/apisix-dashboard) 的 Web 界面完成上述操作。

<!--
![add a consumer](https://raw.githubusercontent.com/apache/apisix/master/docs/assets/images/plugin/wolf-rbac-1.png)

![enable wolf-rbac plugin](https://raw.githubusercontent.com/apache/apisix/master/docs/assets/images/plugin/wolf-rbac-2.png)
-->

## 测试插件

你可以使用 [public-api](../../../en/latest/plugins/public-api.md) 插件来暴露 API.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/wal \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/apisix/plugin/wolf-rbac/login",
    "plugins": {
        "public-api": {}
    }
}'
```

同样，你需要参考上述命令为 `change_pwd` 和 `user_info` 两个 API 配置路由。

现在你可以登录并获取 wolf `rbac_token`：

```shell
curl http://127.0.0.1:9080/apisix/plugin/wolf-rbac/login -i \
-H "Content-Type: application/json" \
-d '{"appid": "restful", "username":"test", "password":"user-password", "authType":1}'
```

```
HTTP/1.1 200 OK
Date: Wed, 24 Jul 2019 10:33:31 GMT
Content-Type: text/plain
Transfer-Encoding: chunked
Connection: keep-alive
Server: APISIX web server
{"rbac_token":"V1#restful#eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6NzQ5LCJ1c2VybmFtZSI6InRlc3QiLCJtYW5hZ2VyIjoiIiwiYXBwaWQiOiJyZXN0ZnVsIiwiaWF0IjoxNTc5NDQ5ODQxLCJleHAiOjE1ODAwNTQ2NDF9.n2-830zbhrEh6OAxn4K_yYtg5pqfmjpZAjoQXgtcuts","user_info":{"nickname":"test","username":"test","id":"749"}}
```

:::note

上述示例中，`appid`、`username` 和 `password` 必须为 wolf 系统中真实存在的。

`authType` 为认证类型，`1` 为密码认证（默认），`2` 为 LDAP 认证。`wolf` 从 0.5.0 版本开始支持了 LDAP 认证。

:::

也可以使用 x-www-form-urlencoded 方式登陆：

```shell
curl http://127.0.0.1:9080/apisix/plugin/wolf-rbac/login -i \
-H "Content-Type: application/x-www-form-urlencoded" \
-d 'appid=restful&username=test&password=user-password'
```

现在开始测试 Route：

- 缺少 token

```shell
curl http://127.0.0.1:9080/ -H"Host: www.baidu.com" -i
```

```shell
HTTP/1.1 401 Unauthorized
...
{"message":"Missing rbac token in request"}
```

- token 放到请求头 (Authorization) 中：

```shell
curl http://127.0.0.1:9080/ -H"Host: www.baidu.com" \
-H 'Authorization: V1#restful#eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6NzQ5LCJ1c2VybmFtZSI6InRlc3QiLCJtYW5hZ2VyIjoiIiwiYXBwaWQiOiJyZXN0ZnVsIiwiaWF0IjoxNTc5NDQ5ODQxLCJleHAiOjE1ODAwNTQ2NDF9.n2-830zbhrEh6OAxn4K_yYtg5pqfmjpZAjoQXgtcuts' -i
```

```shell
HTTP/1.1 200 OK

<!DOCTYPE html>
```

- token 放到请求头 (x-rbac-token) 中：

```shell
curl http://127.0.0.1:9080/ -H"Host: www.baidu.com" \
-H 'x-rbac-token: V1#restful#eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6NzQ5LCJ1c2VybmFtZSI6InRlc3QiLCJtYW5hZ2VyIjoiIiwiYXBwaWQiOiJyZXN0ZnVsIiwiaWF0IjoxNTc5NDQ5ODQxLCJleHAiOjE1ODAwNTQ2NDF9.n2-830zbhrEh6OAxn4K_yYtg5pqfmjpZAjoQXgtcuts' -i
```

```shell
HTTP/1.1 200 OK

<!DOCTYPE html>
```

- token 放到请求参数中：

```shell
curl 'http://127.0.0.1:9080?rbac_token=V1%23restful%23eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6NzQ5LCJ1c2VybmFtZSI6InRlc3QiLCJtYW5hZ2VyIjoiIiwiYXBwaWQiOiJyZXN0ZnVsIiwiaWF0IjoxNTc5NDQ5ODQxLCJleHAiOjE1ODAwNTQ2NDF9.n2-830zbhrEh6OAxn4K_yYtg5pqfmjpZAjoQXgtcuts' -H"Host: www.baidu.com" -i
```

```shell
HTTP/1.1 200 OK

<!DOCTYPE html>
```

- token 放到 `cookie` 中：

```shell
curl http://127.0.0.1:9080 -H"Host: www.baidu.com" \
--cookie x-rbac-token=V1#restful#eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6NzQ5LCJ1c2VybmFtZSI6InRlc3QiLCJtYW5hZ2VyIjoiIiwiYXBwaWQiOiJyZXN0ZnVsIiwiaWF0IjoxNTc5NDQ5ODQxLCJleHAiOjE1ODAwNTQ2NDF9.n2-830zbhrEh6OAxn4K_yYtg5pqfmjpZAjoQXgtcuts -i
```

```shell
HTTP/1.1 200 OK

<!DOCTYPE html>
```

- 获取用户信息：

```shell
curl http://127.0.0.1:9080/apisix/plugin/wolf-rbac/user_info \
--cookie x-rbac-token=V1#restful#eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6NzQ5LCJ1c2VybmFtZSI6InRlc3QiLCJtYW5hZ2VyIjoiIiwiYXBwaWQiOiJyZXN0ZnVsIiwiaWF0IjoxNTc5NDQ5ODQxLCJleHAiOjE1ODAwNTQ2NDF9.n2-830zbhrEh6OAxn4K_yYtg5pqfmjpZAjoQXgtcuts -i
```

```shell
HTTP/1.1 200 OK
{
    "user_info":{
        "nickname":"test",
        "lastLogin":1582816780,
        "id":749,
        "username":"test",
        "appIDs":["restful"],
        "manager":"none",
        "permissions":{"USER_LIST":true},
        "profile":null,
        "roles":{},
        "createTime":1578820506,
        "email":""
    }
}
```

- 更改用户的密码：

```shell
curl http://127.0.0.1:9080/apisix/plugin/wolf-rbac/change_pwd \
-H "Content-Type: application/json" \
--cookie x-rbac-token=V1#restful#eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6NzQ5LCJ1c2VybmFtZSI6InRlc3QiLCJtYW5hZ2VyIjoiIiwiYXBwaWQiOiJyZXN0ZnVsIiwiaWF0IjoxNTc5NDQ5ODQxLCJleHAiOjE1ODAwNTQ2NDF9.n2-830zbhrEh6OAxn4K_yYtg5pqfmjpZAjoQXgtcuts -i \
-X PUT -d '{"oldPassword": "old password", "newPassword": "new password"}'
```

```shell
HTTP/1.1 200 OK
{"message":"success to change password"}
```

## 删除插件

当你需要禁用 `wolf-rbac` 插件时，可以通过以下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/*",
    "plugins": {
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "www.baidu.com:80": 1
        }
    }
}'
```
