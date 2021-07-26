---
title: header-based-routing
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

- [**名字**](#名字)
- [**属性**](#属性)
- [**如何启用**](#如何启用)
- [**测试插件**](#测试插件)
- [**禁用插件**](#禁用插件)

## 名字

`header-based-routing` 可以通过指定请求头来选择不同的上游服务

## 属性

|              参数名             | 类型          | 可选项 | 默认值 | 有效值 | 描述                 |
| --------- | ------------- | ------ | ------ | ------ | -------------------------------- |
| rules.match| array[object] |  必选  |        |        | 匹配规则列表 |
| rules.upstream_name|string |    必选 |        |        |命中规则以后选择的路由名 |

`match` 数组的每一项由下面三个属性组成

|              参数名             | 类型          | 可选项 | 默认值 | 有效值 | 描述                 |
| --------- | ------------- | ------ | ------ | ------ | -------------------------------- |
| name| string |  必选  |        |        | 请求 Header 名|
| values|array[string] |    在 mode 为 exact, prefix, regex 情况下必选 | | | 待匹配的 Header 值列表，满足数组中任意一个即视为满足匹配 |
| mode |string |  必选| |  exact, prefix, regex, exists 这四个枚举值中的一个| 匹配模式: exact 表示精确匹配, prefix 表示前缀匹配, regex 表示正则匹配, exists 表示存在相应 Header 值即可  |

## 如何启用

假如我们有如下四个上游 upstream，请求对应的上游服务返回结果为对应监听的端口号

- my_upstream_1(127.0.0.1:1981)
- my_upstream_2(127.0.0.1:1982)
- my_upstream_3(127.0.0.1:1983)
- my_upstream_4(127.0.0.1:1984)


下面是一个示例，在指定的 route 上开启了 `header-based-routing` 插件:

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
  "uri": "/index.html",
  "upstream": {
    "type": "roundrobin",
    "nodes": {
      "127.0.0.1:1980": 1
    }
  },
  "plugins": {
    "header-based-routing": {
      "rules": [
        {
          "match": [
            {
              "name": "header1",
              "values": [
                "value1",
                "value2"
              ],
              "mode": "exact"
            }
          ],
          "upstream_name": "my_upstream_1"
        },
        {
          "match": [
            {
              "name": "header2",
              "values": [
                "1prefix",
                "2prefix"
              ],
              "mode": "prefix"
            }
          ],
          "upstream_name": "my_upstream_2"
        },
        {
          "match": [
            {
              "name": "header3",
              "values": [
                "(Twitterbot)/(\\d+)\\.(\\d+)"
              ],
              "mode": "regex"
            }
          ],
          "upstream_name": "my_upstream_3"
        },
        {
          "match": [
            {
              "name": "header4",
              "mode": "exists"
            }
          ],
          "upstream_name": "my_upstream_4"
        }
      ]
    }
  }
}'

```

## 测试插件

### exact 完全匹配模式

用户传入 Header 值 `header1=value1` 时，满足完全匹配模式 exact，此时会选择 my_upstream_1 作为上游 upstream

```shell
$ curl http://127.0.0.1:9080/index.html --header 'header1: value1'
1981
```

### prefix 前缀匹配模式

用户传入 Header 值 `header2=1prefix_foo` 时，满足完全前缀模式 prefix，此时会选择 my_upstream_2 作为上游 upstream

```shell
$ curl http://127.0.0.1:9080/index.html --header 'header2: 1prefix_foo'
1982
```

### regex 正则匹配模式

用户传入 Header 值 `header3=Twitterbot/1.1` 时，满足完全正则匹配模式 regex，此时会选择 my_upstream_3 作为上游 upstream

```shell
$ curl http://127.0.0.1:9080/index.html --header 'header3: Twitterbot/1.1'
1983
```

### exists 存在模式

用户传入 Header 值 `header4=foo` 时，满足完全存在匹配模式 exists，此时会选择 my_upstream_4 作为上游 upstream

```shell
$ curl http://127.0.0.1:9080/index.html --header 'header4: foo'
1983
```

当用户传入的 Header 没有满足任何一个条件时，会选择此 Router 默认的上游 upstream


## 禁用插件

当你想去掉 `header-based-routing` 插件的时候，很简单，在插件的配置中把对应的 json 配置删除即可，无须重启服务，即刻生效：

```shell
$ curl http://127.0.0.1:2379/v2/keys/apisix/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d value='
{
    "uri": "/index.html",
    "plugins": {},
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "39.97.63.215:80": 1
        }
    }
}'
```

现在就已移除 `header-based-routing` 插件，其它插件的开启和移除也类似。
