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

[English](response-rewrite.md)
# response-rewrite

该插件支持修改上游服务返回的body和header信息。
可以设置 `ccess-Control-Allow-*` 等header信息，来实现 CORS (跨域资源共享)的功能。

#### 配置参数
|名字    |可选|说明|
|------- |-----|------|
|body          |可选| 修改上游返回的 `body` 内容，如果设置了新内容，header里面的content-type字段也会被修改|
|headers       |可选| 返回给客户端的`headers`，可以设置多个。头信息如果存在将重写，不存在则添加。想要删除某个 header 的话，把对应的值设置为空字符串即可|

### 示例

#### 开启插件
下面是一个示例，在指定的 route 上开启了 `response rewrite` 插件:

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/test/index.html",
    "plugins": {
        "response-rewrite": {
            "body": "under construction",
            "headers": {
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Methods": "GET, POST, OPTIONS"
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
curl -X GET -i  http://127.0.0.1:9080/test/index.html
```

如果看到返回的头部信息和内容都被修改了，即表示 `response rewrite` 插件生效了。
```
HTTP/1.1 200 OK
Server: openresty
Date: Sat, 16 Nov 2019 09:15:12 GMT
Content-Type: text/html
Transfer-Encoding: chunked
Connection: keep-alive
Access-Control-Allow-Origin: *
Access-Control-Allow-Methods: GET, POST, OPTIONS

under construction
```
