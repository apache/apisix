---
title: error-page
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - Error page
  - error-page
description: error-page 插件允许自定义 APISIX 生成的 HTTP 错误响应的响应体和内容类型，例如路由不匹配或上游不可达时返回的错误页面。
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

`error-page` 插件允许自定义 APISIX 本身生成的 HTTP 错误响应（例如，路由不匹配或上游不可达时）的响应体和内容类型。来自上游服务的响应不会受到影响。

该插件通过[插件元数据](../terminology/plugin-metadata.md)进行全局配置，无需在路由上配置属性。启用后，它会拦截错误响应并将响应体替换为配置的自定义内容。

## 插件元数据

该插件不支持在路由、服务或其他资源上配置属性，所有配置均通过插件元数据完成。

| 名称                               | 类型    | 必选项 | 默认值     | 描述                                                                                                           |
| ---------------------------------- | ------- | ------ | ---------- | -------------------------------------------------------------------------------------------------------------- |
| enable                             | boolean | 否     | false      | 设置为 `true` 时，插件拦截错误响应并替换为自定义页面。                                                         |
| error_`{status_code}`              | object  | 否     |            | 指定 HTTP 状态码的自定义错误页面配置，例如 `error_404` 对应 404 响应。支持 100–599 范围内的任意 HTTP 状态码。  |
| error_`{status_code}`.body         | string  | 否     |            | 指定状态码的响应体内容。若为空或未设置，则使用 APISIX/nginx 的默认错误页面。                                   |
| error_`{status_code}`.content_type | string  | 否     | text/html  | 响应体的内容类型。                                                                                              |

## 启用插件

`error-page` 插件默认禁用。要启用该插件，请将其添加到配置文件（`conf/config.yaml`）中：

```yaml title="conf/config.yaml"
plugins:
  - ...
  - error-page
```

## 配置插件元数据

:::note

你可以通过以下命令从 `config.yaml` 中获取 `admin_key` 并保存为环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

配置插件元数据以启用插件并为一个或多个 HTTP 状态码定义自定义错误页面：

```shell
curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/error-page \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "enable": true,
    "error_404": {
        "body": "<html><body><h1>404 - 页面未找到</h1></body></html>",
        "content_type": "text/html"
    },
    "error_500": {
        "body": "<html><body><h1>500 - 服务器内部错误</h1></body></html>",
        "content_type": "text/html"
    },
    "error_502": {
        "body": "<html><body><h1>502 - 网关错误</h1></body></html>",
        "content_type": "text/html"
    },
    "error_503": {
        "body": "<html><body><h1>503 - 服务不可用</h1></body></html>",
        "content_type": "text/html"
    }
}'
```

你也可以通过设置自定义 `content_type` 来返回 JSON 格式的错误响应：

```shell
curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/error-page \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "enable": true,
    "error_404": {
        "body": "{\"code\": 404, \"message\": \"资源未找到\"}",
        "content_type": "application/json"
    },
    "error_500": {
        "body": "{\"code\": 500, \"message\": \"服务器内部错误\"}",
        "content_type": "application/json"
    }
}'
```

由于该插件使用全局元数据，你还需要在路由上启用该插件。可以使用[全局规则](../terminology/global-rule.md)将其应用于所有路由：

```shell
curl http://127.0.0.1:9180/apisix/admin/global_rules/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "plugins": {
        "error-page": {}
    }
}'
```

## 示例

按照上述方式配置插件和元数据后，访问一个不存在的路由触发 404 错误：

```shell
curl -i http://127.0.0.1:9080/non-existent-path
```

```
HTTP/1.1 404 Not Found
Content-Type: text/html
...

<html><body><h1>404 - 页面未找到</h1></body></html>
```

## 禁用插件

若要全局禁用该插件，在插件元数据中将 `enable` 设置为 `false`：

```shell
curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/error-page \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "enable": false
}'
```

若要从路由中完全移除该插件，删除路由插件配置中对应的 JSON 配置。APISIX 将自动重新加载，无需重启。

```shell
curl http://127.0.0.1:9180/apisix/admin/global_rules/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "plugins": {}
}'
```
