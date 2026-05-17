---
title: feishu-auth
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - Feishu Auth
  - feishu-auth
description: This document contains information about the Apache APISIX feishu-auth Plugin.
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

The `feishu-auth` Plugin authenticates requests using the [Feishu (Lark) OAuth 2.0](https://open.feishu.cn/document/uAjLw4CM/ukTMukTMukTM/authentication-management/access-token/oauth-2.0-overview) authorization flow. Users are redirected to the Feishu login page when unauthenticated. After a successful login, Feishu user information is stored in an encrypted session cookie and optionally forwarded to upstream services via the `X-Userinfo` header.

## Attributes

| Name                   | Type     | Required | Default                                                           | Description                                                                                                 |
|------------------------|----------|----------|-------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------|
| `app_id`               | string   | True     |                                                                   | Feishu application App ID.                                                                                  |
| `app_secret`           | string   | True     |                                                                   | Feishu application App Secret.                                                                              |
| `secret`               | string   | True     |                                                                   | Secret used for signing the session cookie (8–32 characters). Must remain stable across restarts.          |
| `auth_redirect_uri`    | string   | True     |                                                                   | Redirect URI registered in the Feishu application for the OAuth flow.                                       |
| `redirect_uri`         | string   | True     |                                                                   | URI to redirect the user to when no authorization code is present (i.e. to start the OAuth flow).          |
| `code_header`          | string   | False    | `"X-Feishu-Code"`                                                 | HTTP header name to extract the Feishu authorization code from.                                             |
| `code_query`           | string   | False    | `"code"`                                                          | Query parameter name to extract the Feishu authorization code from.                                         |
| `access_token_url`     | string   | False    | `"https://open.feishu.cn/open-apis/authen/v2/oauth/token"`       | URL to exchange the authorization code for an access token.                                                 |
| `userinfo_url`         | string   | False    | `"https://open.feishu.cn/open-apis/authen/v1/user_info"`         | URL to retrieve user information using the access token.                                                    |
| `set_userinfo_header`  | boolean  | False    | `true`                                                            | When enabled, sets the `X-Userinfo` request header with Base64-encoded Feishu user information.            |
| `cookie_expires_in`    | integer  | False    | `86400`                                                           | Validity duration (in seconds) for the session cookie.                                                      |
| `secret_fallbacks`     | array    | False    |                                                                   | List of fallback secrets used during key rotation.                                                          |
| `timeout`              | integer  | False    | `6000`                                                            | Timeout (in milliseconds) for HTTP requests to Feishu endpoints.                                            |
| `ssl_verify`           | boolean  | False    | `true`                                                            | When enabled, verifies the SSL certificate when connecting to Feishu endpoints.                             |

## Enable Plugin

You can enable the Plugin on a specific Route as shown below:

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

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

## How It Works

The authentication flow proceeds as follows:

1. A user visits a Route protected by `feishu-auth`.
2. If no valid session cookie exists and no authorization `code` is present, the plugin redirects the user to `redirect_uri` with HTTP 302. Your application should then redirect the user to the Feishu OAuth authorization page.
3. After the user authorizes, Feishu redirects back to `auth_redirect_uri` with an authorization `code`. The plugin extracts the code either from the `code_query` query parameter or the `code_header` HTTP header.
4. The plugin exchanges the code for an access token at `access_token_url`, then fetches user information from `userinfo_url`.
5. User information is stored in an encrypted session cookie (`feishu_session`). Subsequent requests with a valid cookie bypass the OAuth flow.
6. If `set_userinfo_header` is `true`, the plugin encodes the user information as Base64 JSON and sets it in the `X-Userinfo` request header before forwarding to the upstream.

## Delete Plugin

To remove the `feishu-auth` Plugin, delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

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
