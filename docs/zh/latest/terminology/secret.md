---
title: Secret
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

密钥是指 APISIX 运行过程中所需的任何敏感信息，它可能是核心配置的一部分（如 etcd 的密码），也可能是插件中的一些敏感信息。APISIX 中常见的密钥类型包括：

- 一些组件（etcd、Redis、Kafka 等）的用户名、密码
- 证书的私钥
- API 密钥
- 敏感的插件配置字段，通常用于身份验证、hash、签名或加密

APISIX Secret 允许用户在 APISIX 中通过一些密钥管理服务（Vault 等）来存储密钥，在使用的时候根据 key 进行读取，确保密钥在整个平台中不以明文的形式存在。

其工作原理如图所示：
![secret](../../../assets/images/secret.png)

APISIX 目前支持通过以下方式存储密钥：

- [环境变量](#使用环境变量管理密钥)
- [HashiCorp Vault](#使用-vault-管理密钥)

你可以在以下插件的 consumer 配置中通过指定格式的变量来使用 APISIX Secret 功能，比如 `key-auth` 插件。

::: note

如果某个配置项为：`key: "$ENV://ABC"`，当 APISIX Secret 中没有检索到 $ENV://ABC 对应的真实值，那么 key 的值将是 "$ENV://ABC" 而不是 `nil`。

:::

## 使用环境变量管理密钥

使用环境变量来管理密钥意味着你可以将密钥信息保存在环境变量中，在配置插件时通过特定格式的变量来引用环境变量。APISIX 支持引用系统环境变量和通过 Nginx `env` 指令配置的环境变量。

### 引用方式

```
$ENV://$env_name/$sub_key
```

- env_name: 环境变量名称
- sub_key: 当环境变量的值是 JSON 字符串时，获取某个属性的值

如果环境变量的值是字符串类型，如：

```
export JACK_AUTH_KEY=abc
```

则可以通过如下方式引用：

```
$ENV://JACK_AUTH_KEY
```

如果环境变量的值是一个 JSON 字符串，例如：

```
export JACK={"auth-key":"abc","openid-key": "def"}
```

则可以通过如下方式引用：

```
# 获取环境变量 JACK 的 auth-key
$ENV://JACK/auth-key

# 获取环境变量 JACK 的 openid-key
$ENV://JACK/openid-key
```

### 示例：在 key-auth 插件中使用

第一步：APISIX 实例启动前创建环境变量

```
export JACK_AUTH_KEY=abc
```

第二步：在 `key-auth` 插件中引用环境变量

```shell
curl http://127.0.0.1:9180/apisix/admin/consumers \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "username": "jack",
    "plugins": {
        "key-auth": {
            "key": "$ENV://JACK_AUTH_KEY"
        }
    }
}'
```

通过以上步骤，可以将 `key-auth` 插件中的 key 配置保存在环境变量中，而不是在配置插件时明文显示。

## 使用 Vault 管理密钥

使用 Vault 来管理密钥意味着你可以将密钥信息保存在 Vault 服务中，在配置插件时通过特定格式的变量来引用。APISIX 目前支持对接 [Vault KV 引擎的 V1 版本](https://developer.hashicorp.com/vault/docs/secrets/kv/kv-v1)。

### 引用方式

```
$secret://$manager/$id/$secret_name/$key
```

- manager: 密钥管理服务，可以是 Vault、AWS 等
- APISIX Secret 资源 ID，需要与添加 APISIX Secret 资源时指定的 ID 保持一致
- secret_name: 密钥管理服务中的密钥名称
- key：密钥管理服务中密钥对应的 key

### 示例：在 key-auth 插件中使用

第一步：在 Vault 中创建对应的密钥，可以使用如下命令：

```shell
vault kv put apisix/jack auth-key=value
```

第二步：通过 Admin API 添加 Secret 资源，配置 Vault 的地址等连接信息：

```shell
curl http://127.0.0.1:9180/apisix/admin/secrets/vault/1 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "https://127.0.0.1:8200"，
    "prefix": "apisix",
    "token": "root"
}'
```

如果使用 APISIX Standalone 版本，则可以在 `apisix.yaml`  文件中添加如下配置：

```yaml
secrets:
  - id: vault/1
    prefix: apisix
    token: root
    uri: 127.0.0.1:8200
```

第三步：在 `key-auth` 插件中引用 APISIX Secret 资源，填充秘钥信息：

```shell
curl http://127.0.0.1:9180/apisix/admin/consumers \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "username": "jack",
    "plugins": {
        "key-auth": {
            "key": "$secret://vault/1/jack/auth-key"
        }
    }
}'
```

通过上面两步操作，当用户请求命中 `key-auth` 插件时，会通过 APISIX Secret 组件获取到 key 在 Vault 中的真实值。
