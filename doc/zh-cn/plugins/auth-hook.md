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

- [English](../../plugins/auth-hook.md)

# 目录

- [**名字**](#名字)
- [**属性**](#属性)
- [**依赖项**](#依赖项)
- [**如何启用**](#如何启用)
- [**测试插件**](#测试插件)
- [**禁用插件**](#禁用插件)

## 名字

`auth-hook` 是一个认证及授权插件，它需要与 `consumer` 一起配合才能工作。同时需要添加 `auth-hook` 到一个 `service` 或 `route` 中。
auth-hook 功能由自己 auth-server 提供,按照对应的数据结构提供权限认证接口即可。

## 属性

| 名称                      | 类型    | 必选项 | 默认值  | 有效值 | 描述                                                                                                                                                                                                                                                                    |
| ------------------------- | ------- | ------ | ------- | ------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| hook_uri                  | string  | 必选   |         |        | 设置 `auth-server` 的访问路由                                                                                                                                                                                                                                           |
| auth_id                   | string  | 可选   | "unset" |        | 设置`auth_id`, 该`auth_id`需要业务请求携带 header 中`x-auth-id`或者携带在 query 中`auth_id`                                                                                                                                                                             |
| hook_headers              | array[string]   | 可选   |         |        | 指定请求 header 参数 代理请求 hook 服务                                                                                                                                                                                                                                 |
| hook_args                 | array[string]   | 可选   |         |        | 指定请求 query 参数 代理以 query 参数请求 hook 服务                                                                                                                                                                                                                     |
| hook_res_to_headers       | array[string]   | 可选   |         |        | 指定 hook 服务返回数据 data 数据体中的字段，加入 headers 参数传递到上游服务，如 data 数据中有`user_id=15`,将拼接`hook_res_to_header_prefix`并将下`_`替换为`-`放入 header 中，以`X-user-id` 请求上游服务，若选择字段是一个对象或许数组，将转换为 json 字符串作为其 value |
| hook_res_to_header_prefix | string  | 可选   |         |        | 用户`hook_res_to_headers` 携带参数转换为 header 字段的前缀                                                                                                                                                                                                              |
| hook_cache                | boolean | 可选   | false   |        | 是否缓存相同 token 请求 hook 服务的数据体，默认`false` 根据自己业务情况考虑                                                                                                                                                                                             |

## 依赖项

### 部署自己 auth 服务

服务需要提供 auth 接口路由，并且至少需要以下数据结构返回数据数据体，

```json
{
    "message":"success",
    "data":{
        "user_id":15,
        "......":"......"
    }
}
```

## 如何启用

1. 创建一个 consumer 对象，并设置插件 `auth-hook` 的值。

```shell
curl http://127.0.0.1:9080/apisix/admin/consumers  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
  "username": "auth_hook",
  "plugins": {
    "auth-hook": {
      "hook_uri": "http://127.0.0.1/xxxx/xxx",
      "auth_id": "shaozeming",
      "hook_headers": [
        "X-APP-NAME",
        "..."
      ],
      "hook_args": [
        "field_1",
        "..."
      ],
      "hook_res_to_headers": [
        "user_id",
        "..."
      ]
    }
  },
  "desc": "auth-hook"
}'
```

你可以使用浏览器打开 dashboard：`http://127.0.0.1:9080/apisix/dashboard/`，通过 web 界面来完成上面的操作，先增加一个 consumer：
![](../../images/plugin/auth-hook-1.png)

然后在 consumer 页面中添加 auth-hook 插件：
![](../../images/plugin/auth-hook-2.png)

注意: 上面填写的 `appid` 需要在 wolf 控制台中已经存在的.

2. 创建 Route 或 Service 对象，并开启 `auth-hook` 插件。

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/*",
    "plugins": {
        "auth-hook": {}
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "www.baidu.com:80": 1
        }
    }
}'
```

## 测试插件

#### 首先进行登录获取 `auth-hook` token:

下面的 `appid`, `username`, `password` 必须为 wolf 系统中真实存在的.

- 以 POST application/json 方式登陆.

```shell
curl http://127.0.0.1:9080/apisix/plugin/auth-hook/login -i \
-H "Content-Type: application/json" \
-d '{"appid": "restful", "username":"test", "password":"user-password"}'

HTTP/1.1 200 OK
Date: Wed, 24 Jul 2019 10:33:31 GMT
Content-Type: text/plain
Transfer-Encoding: chunked
Connection: keep-alive
Server: APISIX web server
{"rbac_token":"V1#restful#eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6NzQ5LCJ1c2VybmFtZSI6InRlc3QiLCJtYW5hZ2VyIjoiIiwiYXBwaWQiOiJyZXN0ZnVsIiwiaWF0IjoxNTc5NDQ5ODQxLCJleHAiOjE1ODAwNTQ2NDF9.n2-830zbhrEh6OAxn4K_yYtg5pqfmjpZAjoQXgtcuts","user_info":{"nickname":"test","username":"test","id":"749"}}
```

- 以 POST x-www-form-urlencoded 方式登陆

```shell
curl http://127.0.0.1:9080/apisix/plugin/auth-hook/login -i \
-H "Content-Type: application/x-www-form-urlencoded" \
-d 'appid=restful&username=test&password=user-password'
```

#### 使用获取到的 token 进行请求尝试

- 缺少 token

```shell
curl http://127.0.0.1:9080/ -H"Host: www.baidu.com" -i

HTTP/1.1 401 Unauthorized
...
{"message":"Missing rbac token in request"}
```

- token 放到请求头(Authorization)中：

```shell
curl http://127.0.0.1:9080/ -H"Host: www.baidu.com" \
-H 'Authorization: V1#restful#eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6NzQ5LCJ1c2VybmFtZSI6InRlc3QiLCJtYW5hZ2VyIjoiIiwiYXBwaWQiOiJyZXN0ZnVsIiwiaWF0IjoxNTc5NDQ5ODQxLCJleHAiOjE1ODAwNTQ2NDF9.n2-830zbhrEh6OAxn4K_yYtg5pqfmjpZAjoQXgtcuts' -i

HTTP/1.1 200 OK

<!DOCTYPE html>
```

- token 放到请求头(x-rbac-token)中：

```shell
curl http://127.0.0.1:9080/ -H"Host: www.baidu.com" \
-H 'x-rbac-token: V1#restful#eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6NzQ5LCJ1c2VybmFtZSI6InRlc3QiLCJtYW5hZ2VyIjoiIiwiYXBwaWQiOiJyZXN0ZnVsIiwiaWF0IjoxNTc5NDQ5ODQxLCJleHAiOjE1ODAwNTQ2NDF9.n2-830zbhrEh6OAxn4K_yYtg5pqfmjpZAjoQXgtcuts' -i


HTTP/1.1 200 OK

<!DOCTYPE html>
```

- token 放到请求参数中：

```shell
curl 'http://127.0.0.1:9080?rbac_token=V1%23restful%23eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6NzQ5LCJ1c2VybmFtZSI6InRlc3QiLCJtYW5hZ2VyIjoiIiwiYXBwaWQiOiJyZXN0ZnVsIiwiaWF0IjoxNTc5NDQ5ODQxLCJleHAiOjE1ODAwNTQ2NDF9.n2-830zbhrEh6OAxn4K_yYtg5pqfmjpZAjoQXgtcuts' -H"Host: www.baidu.com" -i


HTTP/1.1 200 OK

<!DOCTYPE html>
```

- token 放到 cookie 中：

```shell
curl http://127.0.0.1:9080 -H"Host: www.baidu.com" \
--cookie x-rbac-token=V1#restful#eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6NzQ5LCJ1c2VybmFtZSI6InRlc3QiLCJtYW5hZ2VyIjoiIiwiYXBwaWQiOiJyZXN0ZnVsIiwiaWF0IjoxNTc5NDQ5ODQxLCJleHAiOjE1ODAwNTQ2NDF9.n2-830zbhrEh6OAxn4K_yYtg5pqfmjpZAjoQXgtcuts -i


HTTP/1.1 200 OK

<!DOCTYPE html>
```

#### 获取 `RBAC` 用户信息

```shell
curl http://127.0.0.1:9080/apisix/plugin/auth-hook/user_info \
--cookie x-rbac-token=V1#restful#eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6NzQ5LCJ1c2VybmFtZSI6InRlc3QiLCJtYW5hZ2VyIjoiIiwiYXBwaWQiOiJyZXN0ZnVsIiwiaWF0IjoxNTc5NDQ5ODQxLCJleHAiOjE1ODAwNTQ2NDF9.n2-830zbhrEh6OAxn4K_yYtg5pqfmjpZAjoQXgtcuts -i


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

#### 修改 `RBAC` 用户密码

```shell
curl http://127.0.0.1:9080/apisix/plugin/auth-hook/change_pwd \
-H "Content-Type: application/json" \
--cookie x-rbac-token=V1#restful#eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6NzQ5LCJ1c2VybmFtZSI6InRlc3QiLCJtYW5hZ2VyIjoiIiwiYXBwaWQiOiJyZXN0ZnVsIiwiaWF0IjoxNTc5NDQ5ODQxLCJleHAiOjE1ODAwNTQ2NDF9.n2-830zbhrEh6OAxn4K_yYtg5pqfmjpZAjoQXgtcuts -i \
-X PUT -d '{"oldPassword": "old password", "newPassword": "new password"}'


HTTP/1.1 200 OK
{"message":"success to change password"}
```

## 禁用插件

当你想去掉 `rbac-wolf` 插件的时候，很简单，在 routes 中的插件配置中把对应的 `插件` 配置删除即可，无须重启服务，即刻生效：

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
