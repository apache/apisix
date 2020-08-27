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

- [English](../../plugins/fault-injection.md)

# fault-injection

故障注入插件，该插件可以和其他插件一起使用，并且会在其他插件前被执行，配置 `abort` 参数将直接返回给客户端指定的响应码并且终止其他插件的执行，配置 `delay` 参数将延迟某个请求，并且还会执行配置的其他插件。

## 参数

|名称    |必须|描述|
|------- |-----|------|
|abort.http_status|可选|返回给客户端的 http 状态码|
|abort.body|可选|返回给客户端的响应数据|
|delay.duration|可选|延迟时间，可以指定小数|

注：参数 abort 和 delay 至少要存在一个。

## 示例

### 启用插件

示例1：为特定路由启用 `fault-injection` 插件，并指定 `abort` 参数：

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "plugins": {
       "fault-injection": {
           "abort": {
              "http_status": 200,
              "body": "Fault Injection!"
           }
       }
    },
    "upstream": {
       "nodes": {
           "127.0.0.1:1980": 1
       },
       "type": "roundrobin"
    },
    "uri": "/hello"
}'
```

测试：

```shell
$ curl http://127.0.0.1:9080/hello -i
HTTP/1.1 200 OK
Date: Mon, 13 Jan 2020 13:50:04 GMT
Content-Type: text/plain
Transfer-Encoding: chunked
Connection: keep-alive
Server: APISIX web server

Fault Injection!
```

> http status 返回`200`并且响应`body`为`Fault Injection!`，表示该插件已启用。

示例2：为特定路由启用 `fault-injection` 插件，并指定 `delay` 参数：

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "plugins": {
       "fault-injection": {
           "delay": {
              "duration": 3
           }
       }
    },
    "upstream": {
       "nodes": {
           "127.0.0.1:1980": 1
       },
       "type": "roundrobin"
    },
    "uri": "/hello"
}'
```

测试：

```shell
$ time curl http://127.0.0.1:9080/hello -i
HTTP/1.1 200 OK
Content-Type: application/octet-stream
Content-Length: 6
Connection: keep-alive
Server: APISIX web server
Date: Tue, 14 Jan 2020 14:30:54 GMT
Last-Modified: Sat, 11 Jan 2020 12:46:21 GMT

hello

real    0m3.034s
user    0m0.007s
sys     0m0.010s
```

### 禁用插件

移除插件配置中相应的 JSON 配置可立即禁用该插件，无需重启服务：

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
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

这时该插件已被禁用。
