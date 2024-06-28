---
title: http-dubbo
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - http-dubbo
  - http to dubbo
description: 本文介绍了关于 Apache APISIX `http-dubbo` 插件的基本信息及使用方法。
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

`http-dubbo` 插件可以将 http 请求 encode 为 dubbo 协议转发给上游服务（注意：在 dubbo2.x 时上游服务的序列化类型必须是 fastjson)

## 属性

| 名称                     | 类型    | 必选项 | 默认值 | 有效值      | 描述                                                                                                                                                                                                           |
| ------------------------ | ------- |-----| ------ | ----------- |--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| service_name             | string  | 是   |        |             | dubbo 服务名                                                                                                                                                                                                    |
| service_version          | string  | 否   | 0.0.0  |             | dubbo 服务版本 默认 0.0.0                                                                                                                                                                                          |
| method                   | string  | 是   |        |             | dubbo 服务方法名                                                                                                                                                                                                  |
| params_type_desc         | string  | 否   |        |             | dubbo 服务方法签名描述，入参如果是 void 可不填写                                                                                                                                                                               |
| serialization_header_key | string  | 否   |        |             | 插件会读取该请求头判断 body 是否已经按照 dubbo 协议序列化完毕。如果该请求头的值为 true 则插件不会更改 body 内容，直接把他当作 dubbo 请求参数。如果为 false 则要求开发者按照 dubbo 泛化调用的格式传递参数，由插件进行序列化。注意：由于 lua 和 java 的插件序列化精度不同，可能会导致参数精度不同。 |
| serialized               | boolean | 否   | false  | [true, false] | 和`serialization_header_key`一样。优先级低于`serialization_header_key`                                                                                                                                                |
| connect_timeout          | number  | 否   | 6000   |             | 上游服务 tcp connect_timeout                                                                                                                                                                                     |
| read_timeout             | number  | 否   | 6000   |             | 上游服务 tcp read_timeout                                                                                                                                                                                        |
| send_timeout             | number  | 否   | 6000   |             | 上游服务 tcp send_timeout                                                                                                                                                                                        |

## 启用插件

以下示例展示了如何在指定路由中启用 `http-dubbo` 插件：

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl -i http://127.0.0.1:9180/apisix/admin/routes/1  \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/TestService/testMethod",
    "plugins": {
        "http-dubbo": {
            "method": "testMethod",
            "params_type_desc": "Ljava/lang/Long;Ljava/lang/Integer;",
            "serialized": true,
            "service_name": "com.xxx.xxx.TestService",
            "service_version": "0.0.0"
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```

## 测试插件

通过上述命令启用插件后，可以使用如下命令测试插件是否启用成功：

```shell
curl --location 'http://127.0.0.1:9080/TestService/testMethod' \
--data '1
2'
```

## 如何获取 params_type_desc

```java
Method[] declaredMethods = YourService.class.getDeclaredMethods();
String params_type_desc = ReflectUtils.getDesc(Arrays.stream(declaredMethods).filter(it->it.getName().equals("yourmethod")).findAny().get().getParameterTypes());

//方法重载情况下需要找自己需要暴露的方法  ReflectUtils 为 dubbo 实现
```

## 如何按照 dubbo 协议使用 json 进行序列化

为了防止精度丢失。我们推荐使用序列化好的 body 进行请求。
dubbo 的 fastjson 序列化规则如下：

- 每个参数之间使用 toJSONString 转化为 JSON 字符串

- 每个参数之间使用换行符 `\n` 分隔

部分语言和库在字符串或数字调用 toJSONString 后结果是不变的这可能需要你手动处理一些特殊情况例如：

- 字符串 `abc"` 需要被 encode 为 `"abc\""`

- 字符串 `123` 需要被 encode 为 `"123"`

抽象类，父类或者泛型作为入参签名，入参需要具体类型时。序列化需要写入具体的类型信息具体参考 [WriteClassName](https://github.com/alibaba/fastjson/wiki/SerializerFeature_cn)

## 删除插件

当你需要禁用 `http-dubbo` 插件时，可以通过以下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务。
