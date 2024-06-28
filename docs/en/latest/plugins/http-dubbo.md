---
title: http-dubbo
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - http-dubbo
  - http to dubbo
  - transcode
description: This document contains information about the Apache APISIX http-dubbo Plugin.
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

## Description

The `http-dubbo` plugin can transcode between http and Dubbo (Note: in
Dubbo 2.x, the serialization type of the upstream service must be fastjson).

## Attributes

| Name                     | Type    | Required | Default | Valid values | Description                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
|--------------------------|---------|----------|---------|--------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| service_name             | string  | True     |         |              | Dubbo service name                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| service_version          | string  | False    | 0.0.0   |              | Dubbo service version                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| method                   | string  | True     |         |              | Dubbo service method name                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| params_type_desc         | string  | True     |         |              | Description of the Dubbo service method signature                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| serialization_header_key | string  | False    |         |              | If `serialization_header_key` is set, the plugin will read this request header to determine if the body has already been serialized according to the Dubbo protocol. If the value of this request header is true, the plugin will not modify the body content and will directly consider it as Dubbo request parameters. If it is false, the developer is required to pass parameters in the format of Dubbo's generic invocation, and the plugin will handle serialization. Note: Due to differences in precision between Lua and Java, serialization by the plugin may lead to parameter precision discrepancies. |
| serialized               | boolean | False    | false   | [true, false]  | Same as `serialization_header_key`. Priority is lower than `serialization_header_key`.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| connect_timeout          | number  | False    | 6000    |              | Upstream tcp connect timeout                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| read_timeout             | number  | False    | 6000    |              | Upstream tcp read_timeout                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| send_timeout             | number  | False    | 6000    |              | Upstream tcp send_timeout                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |

## Enable Plugin

The example below enables the `http-dubbo` Plugin on the specified Route:

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

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
            "127.0.0.1:20880": 1
        }
    }
}'
```

## Example usage

Once you have configured the Plugin as shown above, you can make a request as shown below:

```shell
curl --location 'http://127.0.0.1:9080/TestService/testMethod' \
--data '1
2'
```

## How to Get `params_type_desc`

```java
Method[] declaredMethods = YourService.class.getDeclaredMethods();
String params_type_desc = ReflectUtils.getDesc(Arrays.stream(declaredMethods).filter(it -> it.getName().equals("yourmethod")).findAny().get().getParameterTypes());

// If there are method overloads, you need to find the method you want to expose.
// ReflectUtils is a Dubbo implementation.
```

## How to Serialize JSON According to Dubbo Protocol

To prevent loss of precision, we recommend using pre-serialized bodies for requests. The serialization rules for Dubbo's
fastjson are as follows:

- Convert each parameter to a JSON string using toJSONString.
- Separate each parameter with a newline character `\n`.

Some languages and libraries may produce unchanged results when calling toJSONString on strings or numbers. In such
cases, you may need to manually handle some special cases. For example:

- The string `abc"` needs to be encoded as `"abc\""`.
- The string `123` needs to be encoded as `"123"`.

Abstract class, parent class, or generic type as input parameter signature, when the input parameter requires a specific
type. Serialization requires writing specific type information.
Refer to [WriteClassName](https://github.com/alibaba/fastjson/wiki/SerializerFeature_cn) for more details.

## Delete Plugin

To remove the `http-dubbo` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration.
APISIX will automatically reload and you do not have to restart for this to take effect.
