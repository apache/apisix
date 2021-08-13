---
title: xml-json-conversion
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

## 目录

- [**名称**](#名称)
- [**属性**](#属性)
- [**如何开启**](#如何开启)
- [**测试插件**](#测试插件)
- [**禁用插件**](#禁用插件)

## 名称

xml-json-conversion 插件意在将request body中的xml数据转换成json输出,或者将json数据转换成xml数据输出

## 属性

无

## 如何开启

下面是一个示例，如何在指定的路由上开启插件:

```shell
curl -i http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/hello",
    "plugins": {
        "xml-json-conversion": {}
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "39.97.63.215:80": 1
        }
    }
}'
```

## 测试插件

通过curl访问

```shell
curl -X GET http://127.0.0.1:9080/hello \
-H 'Content-Type: text/xml' \
-H 'Accept: application/json' \
--data '
<people>
  <person>
    <name>Manoel</name>
    <city>Palmas-TO</city>
  </person>
</people>'


{"people":{"person":{"name":"Manoel","city":"Palmas-TO"}}}
```

## 禁用插件

想要禁用“xml-json-conversion”插件，是非常简单的，将对应的插件配置从 json 配置删除，就会立即生效，不需要重新启动服务：

```shell
curl -i http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/hello",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "39.97.63.215:80": 1
        }
    }
}'
```
