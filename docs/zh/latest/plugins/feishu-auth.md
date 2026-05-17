---
title: feishu-auth
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - Feishu Auth
  - feishu-auth
description: 本篇文档介绍了 Apache APISIX feishu-auth 插件的相关信息。
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

`feishu-auth` 插件使用[飞书（Lark）OAuth 2.0](https://open.feishu.cn/document/uAjLw4CM/ukTMukTMukTM/authentication-management/access-token/oauth-2.0-overview) 授权流程对请求进行认证。未认证的用户将被重定向到飞书登录页面，登录成功后，飞书用户信息将存储在加密的 session Cookie 中，并可通过 `X-Userinfo` 请求头转发给上游服务。

## 属性

| 名称                  | 类型    | 必选项 | 默认值                                                             | 描述                                                                                         |
|-----------------------|---------|--------|--------------------------------------------------------------------|----------------------------------------------------------------------------------------------|
| `app_id`              | string  | 是     |                                                                    | 飞书应用的 App ID。                                                                          |
| `app_secret`          | string  | 是     |                                                                    | 飞书应用的 App Secret。                                                                      |
| `secret`              | string  | 是     |                                                                    | 用于签名 session Cookie 的密钥（8-32 个字符），重启后需保持不变。                           |
| `auth_redirect_uri`   | string  | 是     |                                                                    | 在飞书应用中注册的 OAuth 重定向 URI。                                                        |
| `redirect_uri`        | string  | 是     |                                                                    | 当请求中不含授权码时，将用户重定向到此 URI 以发起 OAuth 授权流程。                          |
| `code_header`         | string  | 否     | `"X-Feishu-Code"`                                                  | 从 HTTP 请求头中提取飞书授权码所使用的请求头名称。                                           |
| `code_query`          | string  | 否     | `"code"`                                                           | 从 URL 查询参数中提取飞书授权码所使用的参数名称。                                            |
| `access_token_url`    | string  | 否     | `"https://open.feishu.cn/open-apis/authen/v2/oauth/token"`        | 使用授权码换取 access token 的接口地址。                                                     |
| `userinfo_url`        | string  | 否     | `"https://open.feishu.cn/open-apis/authen/v1/user_info"`          | 使用 access token 获取用户信息的接口地址。                                                   |
| `set_userinfo_header` | boolean | 否     | `true`                                                             | 开启后，插件将飞书用户信息以 Base64 编码的 JSON 格式设置到 `X-Userinfo` 请求头中。          |
| `cookie_expires_in`   | integer | 否     | `86400`                                                            | session Cookie 的有效时长（秒）。                                                            |
| `secret_fallbacks`    | array   | 否     |                                                                    | 密钥轮换时使用的备用密钥列表。                                                               |
| `timeout`             | integer | 否     | `6000`                                                             | 请求飞书接口的超时时间（毫秒）。                                                             |
| `ssl_verify`          | boolean | 否     | `true`                                                             | 开启后，连接飞书接口时会验证 SSL 证书。                                                      |

注意：schema 中定义了 `encrypt_fields = {"app_secret", "secret"}`，这意味着这些字段将会被加密存储在 etcd 中。具体参考[加密存储字段](../plugin-develop.md#加密存储字段)。

## 启用插件

以下示例展示了如何在指定路由上启用 `feishu-auth` 插件：

:::note

你可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/api/*",
    "plugins": {
        "feishu-auth": {
            "app_id": "cli_xxxxxxxxxx",
            "app_secret": "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
            "secret": "my-session-secret",
            "auth_redirect_uri": "https://your-domain.com/api/callback",
            "redirect_uri": "https://your-domain.com/oauth/feishu"
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:8080": 1
        }
    }
}'
```

## 工作原理

认证流程如下：

1. 用户访问受 `feishu-auth` 插件保护的路由。
2. 若不存在有效的 session Cookie 且请求中不含授权 `code`，插件将以 HTTP 302 重定向用户至 `redirect_uri`。你的应用随后应将用户重定向到飞书 OAuth 授权页面。
3. 用户授权后，飞书将携带授权 `code` 重定向回 `auth_redirect_uri`。插件从 `code_query` 查询参数或 `code_header` 请求头中提取该授权码。
4. 插件向 `access_token_url` 发起请求，使用授权码换取 access token，再从 `userinfo_url` 获取用户信息。
5. 用户信息存储在加密的 session Cookie（`feishu_session`）中。后续携带有效 Cookie 的请求将跳过 OAuth 流程。
6. 若 `set_userinfo_header` 为 `true`，插件将用户信息 Base64 编码后设置到 `X-Userinfo` 请求头，随请求转发至上游服务。

## 删除插件

如需禁用 `feishu-auth` 插件，可删除插件配置中对应的 JSON 配置。APISIX 将自动重新加载，无需重启。

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/api/*",
    "plugins": {},
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:8080": 1
        }
    }
}'
```
