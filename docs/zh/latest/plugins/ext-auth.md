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

`ext-auth` 通过调用外部授权服务来检查传入请求是否经过授权。如果该请求被网络过滤器认为是未经授权的，那么连接将被关闭。
我们将过`ext-auth` 配置为过滤器链中的第一个过滤器，以便在其余过滤器处理请求之前对请求进行授权。


## 属性

| 名称                      | 类型          | 必选项 | 默认值  | 有效值 | 描述                                                                                                                                                                                                                                                                    |
| ------------------------- | ------------- | ------ | ------- | ------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| ext_auth_url             | string        | 必选   |         |        | 设置`auth-server` 的访问路由 插件会自动携带请求的`path,action,client_ip`携带到域名后面作为 query 参数`?path=path&action=action&client_ip=client_ip`                                                                                                      |
| ext_auth_id              | string        | 可选   | "unset" |        | 设置`ext_auth_id`, 该`ext_auth_id`将携带在 header 中`Auth-Hook-Id`请求自定义的 auth-server 服务                                                                                                                                                                       |
| ext_auth_method          | string        | 可选   | "GET"   |        | 设置 `auth-server` 的访问方法，默认是`GET`,只允许`POST`,`GET`                                                                                                                                                                                                           |
| ext_headers              | array[string] | 可选   |         |        | 指定业务请求的 header 参数 代理请求 ext_auth 服务，默认会携带`Authorization`                                                                                                                                                                                                |
| ext_args                 | array[string] | 可选   |         |        | 指定请求 query 参数 代理以 query 参数请求 ext_auth 服务                                                                                                                                                                                                                     |
| ext_auth_res_to_headers       | array[string] | 可选   |         |        | |
| ext_auth_res_to_header_prefix | string        | 可选   |     |        | |                                                                                                                                                                                                     |
| ext_auth_cache                | boolean       | 可选   | false   |        | 是否缓存相同 token 请求 ext_auth 服务的数据体，默认`false` 根据自己业务情况考虑,若开启，将缓存 60S                                                                                                                                                                          |
| check_termination         | boolean       | 可选   | true    |        | 是否请求 auth-server 验证后立即中断请求并返回错误信息，`true` 默认开启立即拦截返回，若设置`false` ，auth-server 若返回错误，也将继续放行，同时将 `ext_auth_res_to_headers` 设置的所有映射 header 字段删除。                                                                 |

## 依赖项

### 部署自己 auth 服务

服务需要提供 auth 接口路由，并且至少需要以下数据结构返回数据数据体，我们需要其中的`data`数据体

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

1. 创建 Route 或 Service 对象，并开启 `ext-auth` 插件。

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/*",
    "plugins": {
        "auth-hook": {
            "ext_auth_id": "order",
            "ext_auth_method": "POST",
            "ext_auth_url": "http://common-user-pro_1.dev.xthktech.cn/api/user/gateway-auth",
            "ext_auth_cache": false,
            "ext_auth_check_termination": true,
            "ext_auth_headers": [
                "X-app-name"   ],
            "ext_auth_res_to_header_prefix": "XT-",
            "ext_auth_res_to_header": [
                "user_id",
                "student_id"]
            }
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

```

## 禁用插件

当你想去掉 `ext-auth` 插件的时候，很简单，在 routes 中的插件配置中把对应的 `插件` 配置删除即可，无须重启服务，即刻生效：

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