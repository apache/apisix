---
title: dingtalk-auth
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - DingTalk Auth
  - dingtalk-auth
description: This document contains information about the Apache APISIX dingtalk-auth Plugin.
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

The `dingtalk-auth` Plugin integrates [DingTalk](https://www.dingtalk.com/) OAuth 2.0 authentication into APISIX routes. It validates a DingTalk authorization code, exchanges it for an access token, and retrieves user information from the DingTalk open platform. Verified user information is cached in a secure cookie session so that subsequent requests are not interrupted.

## Attributes

| Name               | Type     | Required | Default                                                   | Description                                                                                                           |
|--------------------|----------|----------|-----------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------|
| `app_key`          | string   | True     |                                                           | DingTalk application App Key (client ID).                                                                             |
| `app_secret`       | string   | True     |                                                           | DingTalk application App Secret (client secret). This field is stored encrypted.                                      |
| `secret`           | string   | True     |                                                           | Key used to sign and encrypt the cookie session (8–32 characters). This field is stored encrypted.                    |
| `redirect_uri`     | string   | True     |                                                           | URI to redirect the user to when no valid authorization code or session is present.                                   |
| `code_header`      | string   | False    | `X-DingTalk-Code`                                         | HTTP request header name from which to read the DingTalk authorization code.                                         |
| `code_query`       | string   | False    | `code`                                                    | Query parameter name from which to read the DingTalk authorization code.                                             |
| `access_token_url` | string   | False    | `https://api.dingtalk.com/v1.0/oauth2/accessToken`        | DingTalk endpoint used to obtain an access token.                                                                     |
| `userinfo_url`     | string   | False    | `https://oapi.dingtalk.com/topapi/v2/user/getuserinfo`    | DingTalk endpoint used to retrieve user information.                                                                  |
| `set_userinfo_header` | boolean | False | `true`                                                   | When `true`, the verified user information is Base64-encoded and forwarded to the upstream in the `X-Userinfo` header. |
| `timeout`          | integer  | False    | `6000`                                                    | Timeout in milliseconds for HTTP calls to DingTalk APIs.                                                              |
| `ssl_verify`       | boolean  | False    | `true`                                                    | Whether to verify the SSL certificate when calling DingTalk APIs.                                                     |
| `cookie_expires_in` | integer | False   | `86400`                                                   | Cookie session validity period in seconds.                                                                            |
| `secret_fallbacks` | array    | False    |                                                           | List of fallback secrets used during key rotation (each 8–32 characters).                                             |

:::note

`encrypt_fields = {"app_secret", "secret"}` is defined in the schema, which means both fields are stored encrypted in etcd. See [encrypted storage fields](../plugin-develop.md#encrypted-storage-fields).

:::

## Authentication flow

```
Client                     APISIX (dingtalk-auth)            DingTalk
  │                               │                               │
  │──── GET /resource ───────────►│                               │
  │                               │  (no session, no code)        │
  │◄─── 302 → redirect_uri ───────│                               │
  │                               │                               │
  │──── GET /resource?code=xxx ──►│                               │
  │                               │──── POST /accessToken ───────►│
  │                               │◄─── {"accessToken": "..."} ───│
  │                               │──── POST /getuserinfo ────────►│
  │                               │◄─── {"result": {...}} ─────────│
  │                               │  (save userinfo in session)   │
  │◄─── 200 + Set-Cookie ─────────│                               │
  │                               │                               │
  │──── GET /resource (Cookie) ──►│                               │
  │                               │  (session valid, skip auth)   │
  │◄─── 200 ──────────────────────│                               │
```

## Enable Plugin

You can enable the Plugin on a specific Route as shown below:

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
  -H "X-API-KEY: $admin_key" \
  -X PUT \
  -d '{
    "methods": ["GET"],
    "uri": "/anything/*",
    "plugins": {
      "dingtalk-auth": {
        "app_key": "<your-app-key>",
        "app_secret": "<your-app-secret>",
        "secret": "<session-secret-key>",
        "redirect_uri": "https://login.dingtalk.com/oauth2/auth?..."
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```

## Example usage

Once you have enabled the Plugin, incoming requests to the Route are processed as follows:

1. **No session and no code**: The user is redirected to `redirect_uri` (typically a DingTalk OAuth login page) with a `302` response.
2. **Authorization code present** (in the `code` query parameter or `X-DingTalk-Code` header): The Plugin exchanges the code for an access token via `access_token_url`, then retrieves user information from `userinfo_url`. On success, the user information is stored in an encrypted cookie session and the original request proceeds.
3. **Valid session cookie**: Subsequent requests carrying the session cookie bypass DingTalk API calls entirely and proceed directly to the upstream.

When `set_userinfo_header` is `true` (the default), the upstream receives the DingTalk user information in the `X-Userinfo` header as a Base64-encoded JSON object.

### Custom code extraction

By default the Plugin reads the authorization code from the `code` query parameter or the `X-DingTalk-Code` header. You can customize both names:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
  -H "X-API-KEY: $admin_key" \
  -X PUT \
  -d '{
    "methods": ["GET"],
    "uri": "/anything/*",
    "plugins": {
      "dingtalk-auth": {
        "app_key": "<your-app-key>",
        "app_secret": "<your-app-secret>",
        "secret": "<session-secret-key>",
        "redirect_uri": "https://login.dingtalk.com/oauth2/auth?...",
        "code_query": "dt_code",
        "code_header": "X-Custom-DT-Code"
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```

### Key rotation

Use `secret_fallbacks` to rotate the session signing key without invalidating existing sessions:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
  -H "X-API-KEY: $admin_key" \
  -X PUT \
  -d '{
    "methods": ["GET"],
    "uri": "/anything/*",
    "plugins": {
      "dingtalk-auth": {
        "app_key": "<your-app-key>",
        "app_secret": "<your-app-secret>",
        "secret": "<new-secret-key>",
        "secret_fallbacks": ["<old-secret-key>"],
        "redirect_uri": "https://login.dingtalk.com/oauth2/auth?..."
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```

## Delete Plugin

To remove the `dingtalk-auth` Plugin, delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
  -H "X-API-KEY: $admin_key" \
  -X PUT \
  -d '{
    "methods": ["GET"],
    "uri": "/anything/*",
    "plugins": {},
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```
