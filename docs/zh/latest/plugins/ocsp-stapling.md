---
title: ocsp-stapling
keywords:
  - Apache APISIX
  - API 网关
  - 插件
  - ocsp-stapling
description: 本文介绍了 API 网关 Apache APISIX ocsp-stapling 插件的相关信息。
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

`ocsp-stapling` 插件可以动态地设置 Nginx 中 [OCSP stapling](https://nginx.org/en/docs/http/ngx_http_ssl_module.html#ssl_stapling) 的相关行为。

## 启用插件

这个插件是默认禁用的，通过修改配置文件 `./conf/config.yaml` 来启用它：

```yaml
plugins:
  - ...
  - ocsp-stapling
```

修改配置文件之后，重启 APISIX 或者通过插件热加载接口来使配置生效：

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/plugins/reload -H "X-API-KEY: $admin_key" -X PUT
```

## 属性

插件属性存储在 SSL 资源的 `ocsp_stapling` 字段中。

| 名称           | 类型                 | 必选项   | 默认值          | 有效值       | 描述                                                                  |
|----------------|----------------------|----------|---------------|--------------|-----------------------------------------------------------------------|
| enabled        | boolean              | False    | false         |              | 与 `ssl_stapling` 指令类似，用于启用或禁用 OCSP stapling 特性            |
| skip_verify    | boolean              | False    | false         |              | 与 `ssl_stapling_verify` 指令类似，用于启用或禁用对于 OCSP 响应结果的校验 |
| cache_ttl      | integer              | False    | 3600          | >= 60        | 指定 OCSP 响应结果的缓存时间                                            |

## 使用示例

首先您应该创建一个 SSL 资源，并且证书资源中应该包含颁发者的证书。通常情况下，全链路证书就可以正常工作。

如下示例中，生成相关的 SSL 资源：

```shell
curl http://127.0.0.1:9180/apisix/admin/ssls/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "cert" : "'"$(cat server.crt)"'",
    "key": "'"$(cat server.key)"'",
    "snis": ["test.com"],
    "ocsp_stapling": {
        "enabled": true
    }
}'
```

通过上述命令生成 SSL 资源后，可以通过以下方法测试：

```shell
echo -n "Q" | openssl s_client -status -connect localhost:9443 -servername test.com 2>&1 | cat
```

```
...
CONNECTED(00000003)
OCSP response:
======================================
OCSP Response Data:
    OCSP Response Status: successful (0x0)
...
```

可以通过以下方法禁用插件：

```shell
curl http://127.0.0.1:9180/apisix/admin/ssls/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "cert" : "'"$(cat server.crt)"'",
    "key": "'"$(cat server.key)"'",
    "snis": ["test.com"],
    "ocsp_stapling": {
        "enabled": false
    }
}'
```

## 删除插件

在删除插件之前，需要确保所有的 SSL 资源都已经移除 `ocsp_stapling` 字段，可以通过以下命令实现对单个 SSL 资源的对应字段移除：

```shell
curl http://127.0.0.1:9180/apisix/admin/ssls/1 \
-H "X-API-KEY: $admin_key" -X PATCH -d '
{
    "ocsp_stapling": null
}'
```

通过修改配置文件 `./conf/config.yaml` 来禁用它：

```yaml
plugins:
  - ...
  # - ocsp-stapling
```

修改配置文件之后，重启 APISIX 或者通过插件热加载接口来使配置生效：

```shell
curl http://127.0.0.1:9180/apisix/admin/plugins/reload -H "X-API-KEY: $admin_key" -X PUT
```
