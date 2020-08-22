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

- [中文](../zh-cn/plugins/wolf-rbac.md)

# Summary

- [**Name**](#name)
- [**Attributes**](#attributes)
- [**Dependencies**](#dependencies)
- [**How To Enable**](#how-to-enable)
- [**Test Plugin**](#test-plugin)
- [**Disable Plugin**](#disable-plugin)

## Name

`wolf-rbac` is an authentication and authorization (rbac) plugin. It needs to work with `consumer`. Also need to add `wolf-rbac` to a` service` or `route`.
The rbac feature is provided by [wolf](https://github.com/iGeeky/wolf). For more information about `wolf`, please refer to [wolf documentation](https://github.com/iGeeky/wolf).


## Attributes

* `server`: Set the service address of` wolf-server`. If not set, the default is: `http://127.0.0.1:10080`.
* `appid`: Set the app id. The app id must be added in wolf-console.
* `header_prefix`: prefix of custom HTTP header. The default value is `X-`. After authentication is successful, three headers will be added to the request header (for backend) and response header (for frontend): `X-UserId`, `X-Username`, `X-Nickname`.


## Dependencies

### Install wolf and start the service

[Wolf quick start](https://github.com/iGeeky/wolf/blob/master/quick-start-with-docker/README.md)

### Add `application`,` admin`, `normal user`,` permission`, `resource` and user authorize

[Wolf-console usage](https://github.com/iGeeky/wolf/blob/master/docs/usage.md)


## How To Enable

1. set a consumer and config the value of the `wolf-rbac`。

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

You can visit the dashboard: `http://127.0.0.1:9080/apisix/dashboard/`, to complete the above operations through the web interface, first add a consumer:
![](../images/plugin/wolf-rbac-1.png)

Then add the wolf-rbac plugin to the consumer page:
![](../images/plugin/wolf-rbac-2.png)

Notes: The `appid` filled in above needs to already exist in the wolf system.

1. Add a `Route` or `Service` and enable the wolf-rbac plugin.

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

## Test Plugin

#### Login and get `wolf-rbac` token:

The following `appid`,` username`, and `password` must be real ones in the wolf system.

* Login as `POST application/json`

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

* Login as `POST x-www-form-urlencoded`

```shell
curl http://127.0.0.1:9080/apisix/plugin/wolf-rbac/login -i \
-H "Content-Type: application/x-www-form-urlencoded" \
-d 'appid=restful&username=test&password=user-password'
```


#### try request with token

* without token

```shell
curl http://127.0.0.1:9080/ -H"Host: www.baidu.com" -i

HTTP/1.1 401 Unauthorized
...
{"message":"Missing rbac token in request"}
```

* request header(Authorization) with token:

```shell
curl http://127.0.0.1:9080/ -H"Host: www.baidu.com" \
-H 'Authorization: V1#restful#eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6NzQ5LCJ1c2VybmFtZSI6InRlc3QiLCJtYW5hZ2VyIjoiIiwiYXBwaWQiOiJyZXN0ZnVsIiwiaWF0IjoxNTc5NDQ5ODQxLCJleHAiOjE1ODAwNTQ2NDF9.n2-830zbhrEh6OAxn4K_yYtg5pqfmjpZAjoQXgtcuts' -i

HTTP/1.1 200 OK

<!DOCTYPE html>
```

* request header(x-rbac-token) with token:

```shell
curl http://127.0.0.1:9080/ -H"Host: www.baidu.com" \
-H 'x-rbac-token: V1#restful#eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6NzQ5LCJ1c2VybmFtZSI6InRlc3QiLCJtYW5hZ2VyIjoiIiwiYXBwaWQiOiJyZXN0ZnVsIiwiaWF0IjoxNTc5NDQ5ODQxLCJleHAiOjE1ODAwNTQ2NDF9.n2-830zbhrEh6OAxn4K_yYtg5pqfmjpZAjoQXgtcuts' -i


HTTP/1.1 200 OK

<!DOCTYPE html>
```

* request params with token:

```shell
curl 'http://127.0.0.1:9080?rbac_token=V1%23restful%23eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6NzQ5LCJ1c2VybmFtZSI6InRlc3QiLCJtYW5hZ2VyIjoiIiwiYXBwaWQiOiJyZXN0ZnVsIiwiaWF0IjoxNTc5NDQ5ODQxLCJleHAiOjE1ODAwNTQ2NDF9.n2-830zbhrEh6OAxn4K_yYtg5pqfmjpZAjoQXgtcuts' -H"Host: www.baidu.com" -i


HTTP/1.1 200 OK

<!DOCTYPE html>
```

* request cookie with token:

```shell
curl http://127.0.0.1:9080 -H"Host: www.baidu.com" \
--cookie x-rbac-token=V1#restful#eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6NzQ5LCJ1c2VybmFtZSI6InRlc3QiLCJtYW5hZ2VyIjoiIiwiYXBwaWQiOiJyZXN0ZnVsIiwiaWF0IjoxNTc5NDQ5ODQxLCJleHAiOjE1ODAwNTQ2NDF9.n2-830zbhrEh6OAxn4K_yYtg5pqfmjpZAjoQXgtcuts -i


HTTP/1.1 200 OK

<!DOCTYPE html>
```


#### Get `RBAC` user information

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

#### Change 'RBAC' user password

```shell
curl http://127.0.0.1:9080/apisix/plugin/wolf-rbac/change_pwd \
-H "Content-Type: application/json" \
--cookie x-rbac-token=V1#restful#eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6NzQ5LCJ1c2VybmFtZSI6InRlc3QiLCJtYW5hZ2VyIjoiIiwiYXBwaWQiOiJyZXN0ZnVsIiwiaWF0IjoxNTc5NDQ5ODQxLCJleHAiOjE1ODAwNTQ2NDF9.n2-830zbhrEh6OAxn4K_yYtg5pqfmjpZAjoQXgtcuts -i \
-X PUT -d '{"oldPassword": "old password", "newPassword": "new password"}'


HTTP/1.1 200 OK
{"message":"success to change password"}
```

## Disable Plugin

When you want to disable the `wolf-rbac` plugin, it is very simple,
 you can delete the corresponding json configuration in the plugin configuration,
  no need to restart the service, it will take effect immediately:

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

