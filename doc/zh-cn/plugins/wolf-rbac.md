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

[English](../../plugins/wolf-rbac.md)

# 目录

- [**名字**](#名字)
- [**属性**](#属性)
- [**依赖项**](#依赖项)
- [**如何启用**](#如何启用)
- [**测试插件**](#测试插件)
- [**禁用插件**](#禁用插件)

## 名字

`wolf-rbac` 是一个认证及授权(rbac)插件，它需要与 `consumer` 一起配合才能工作。同时需要添加 `wolf-rbac` 到一个 `service` 或 `route` 中。
rbac功能由[wolf](https://github.com/iGeeky/wolf)提供, 有关 `wolf` 的更多信息, 请参考[wolf文档](https://github.com/iGeeky/wolf)。


## 属性

* `server`: 设置 `wolf-server` 的访问地址, 如果未设置, 默认为: `http://127.0.0.1:10080`.
* `appid`: 设置应用id, 该应用id, 需要是在 `wolf-console` 中已经添加的应用id.
* `header_prefix`: 自定义http头的前缀, 默认为: `X-`. `wolf-rbac`在鉴权成功后, 会在请求头(用于传给后端)及响应头(用于传给前端)中添加3个头: `X-UserId`, `X-Username`, `X-Nickname`.

## 依赖项

### 安装 wolf, 并启动服务

[Wolf快速起步](https://github.com/iGeeky/wolf/blob/master/quick-start-with-docker/README-CN.md)

### 添加应用, 管理员, 普通用户, 权限, 资源 及给用户授权.

[Wolf管理使用](https://github.com/iGeeky/wolf/blob/master/docs/usage.md)


## 如何启用

1. 创建一个 consumer 对象，并设置插件 `wolf-rbac` 的值。

```shell
curl http://127.0.0.1:9080/apisix/admin/consumers  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
  "username":"wolf_rbac",
  "plugins":{
    "wolf-rbac":{
      "server":"http://127.0.0.1:10080",
      "appid":"restful"
    }
  },
  "desc":"wolf-rbac"
}'
```

你可以使用浏览器打开 dashboard：`http://127.0.0.1:9080/apisix/dashboard/`，通过 web 界面来完成上面的操作，先增加一个 consumer：
![](../../images/plugin/wolf-rbac-1.png)

然后在 consumer 页面中添加 wolf-rbac 插件：
![](../../images/plugin/wolf-rbac-2.png)

注意: 上面填写的 `appid` 需要在wolf控制台中已经存在的.

2. 创建 Route 或 Service 对象，并开启 `wolf-rbac` 插件。

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

## 测试插件

#### 首先进行登录获取 `wolf-rbac` token:

下面的 `appid`, `username`, `password` 必须为wolf系统中真实存在的.

* 以POST application/json方式登陆.

```shell
curl http://127.0.0.1:9080/apisix/plugin/wolf-rbac/login -i \
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

* 以POST x-www-form-urlencoded方式登陆

```shell
curl http://127.0.0.1:9080/apisix/plugin/wolf-rbac/login -i \
-H "Content-Type: application/x-www-form-urlencoded" \
-d 'appid=restful&username=test&password=user-password'
```


#### 使用获取到的 token 进行请求尝试

* 缺少 token

```shell
curl http://127.0.0.1:9080/ -H"Host: www.baidu.com" -i

HTTP/1.1 401 Unauthorized
...
{"message":"Missing rbac token in request"}
```

* token 放到请求头(Authorization)中：

```shell
curl http://127.0.0.1:9080/ -H"Host: www.baidu.com" \
-H 'Authorization: V1#restful#eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6NzQ5LCJ1c2VybmFtZSI6InRlc3QiLCJtYW5hZ2VyIjoiIiwiYXBwaWQiOiJyZXN0ZnVsIiwiaWF0IjoxNTc5NDQ5ODQxLCJleHAiOjE1ODAwNTQ2NDF9.n2-830zbhrEh6OAxn4K_yYtg5pqfmjpZAjoQXgtcuts' -i

HTTP/1.1 200 OK

<!DOCTYPE html>
```

* token 放到请求头(x-rbac-token)中：

```shell
curl http://127.0.0.1:9080/ -H"Host: www.baidu.com" \
-H 'x-rbac-token: V1#restful#eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6NzQ5LCJ1c2VybmFtZSI6InRlc3QiLCJtYW5hZ2VyIjoiIiwiYXBwaWQiOiJyZXN0ZnVsIiwiaWF0IjoxNTc5NDQ5ODQxLCJleHAiOjE1ODAwNTQ2NDF9.n2-830zbhrEh6OAxn4K_yYtg5pqfmjpZAjoQXgtcuts' -i


HTTP/1.1 200 OK

<!DOCTYPE html>
```

* token 放到请求参数中：

```shell
curl 'http://127.0.0.1:9080?rbac_token=V1%23restful%23eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6NzQ5LCJ1c2VybmFtZSI6InRlc3QiLCJtYW5hZ2VyIjoiIiwiYXBwaWQiOiJyZXN0ZnVsIiwiaWF0IjoxNTc5NDQ5ODQxLCJleHAiOjE1ODAwNTQ2NDF9.n2-830zbhrEh6OAxn4K_yYtg5pqfmjpZAjoQXgtcuts' -H"Host: www.baidu.com" -i


HTTP/1.1 200 OK

<!DOCTYPE html>
```

* token 放到 cookie 中：

```shell
curl http://127.0.0.1:9080 -H"Host: www.baidu.com" \
--cookie x-rbac-token=V1#restful#eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6NzQ5LCJ1c2VybmFtZSI6InRlc3QiLCJtYW5hZ2VyIjoiIiwiYXBwaWQiOiJyZXN0ZnVsIiwiaWF0IjoxNTc5NDQ5ODQxLCJleHAiOjE1ODAwNTQ2NDF9.n2-830zbhrEh6OAxn4K_yYtg5pqfmjpZAjoQXgtcuts -i


HTTP/1.1 200 OK

<!DOCTYPE html>
```

#### 获取 `RBAC` 用户信息

```shell
curl http://127.0.0.1:9080/apisix/plugin/wolf-rbac/user_info \
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
curl http://127.0.0.1:9080/apisix/plugin/wolf-rbac/change_pwd \
-H "Content-Type: application/json" \
--cookie x-rbac-token=V1#restful#eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6NzQ5LCJ1c2VybmFtZSI6InRlc3QiLCJtYW5hZ2VyIjoiIiwiYXBwaWQiOiJyZXN0ZnVsIiwiaWF0IjoxNTc5NDQ5ODQxLCJleHAiOjE1ODAwNTQ2NDF9.n2-830zbhrEh6OAxn4K_yYtg5pqfmjpZAjoQXgtcuts -i \
-X PUT -d '{"oldPassword": "old password", "newPassword": "new password"}'


HTTP/1.1 200 OK
{"message":"success to change password"}
```


## 禁用插件

当你想去掉 `rbac-wolf` 插件的时候，很简单，在routes中的插件配置中把对应的 `插件` 配置删除即可，无须重启服务，即刻生效：

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

