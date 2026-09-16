---
title: WebSocket Authentication
keywords:
  - API Gateway
  - Apache APISIX
  - WebSocket
  - Authentication
description: Configure Apache APISIX to authenticate a WebSocket HTTP upgrade request and understand the browser, session, and upstream security boundaries.
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

A WebSocket connection begins as an HTTP upgrade request. Apache APISIX can run an authentication plugin on that handshake and reject the request before the upstream returns `101 Switching Protocols`. After the upgrade succeeds, APISIX proxies WebSocket frames; HTTP authentication plugins are not re-run for each frame.

This tutorial uses [`key-auth`](../plugins/key-auth.md) to demonstrate handshake authentication for a non-browser client that can set a custom header.

## WebSocket authentication boundaries

Design the connection lifecycle before choosing a credential:

- Standard browser WebSocket APIs cannot set an arbitrary `apikey` or `Authorization` header. Do not put a long-lived secret in the URL to work around that limitation. Use an application-specific short-lived ticket, a protected session established over HTTPS, or another browser-compatible design whose replay and authorization behavior you have defined.
- Browser CORS policy does not automatically authorize a WebSocket connection. Validate the `Origin` at a trusted component when your application relies on an origin allowlist.
- A successful handshake authenticates the connection at that moment. If a credential expires or is revoked, the application must define whether to close, reauthenticate, or otherwise reauthorize an existing long-lived connection.
- The upstream service still owns per-message and resource-level authorization. It must not trust identity headers supplied directly by the client; the gateway should strip or overwrite them at the trust boundary.

## Prerequisites

Before you begin, ensure that you have:

1. Apache APISIX installed and the Admin API reachable from an operator environment. The `tls.verify` setting used below requires an [APISIX-Runtime build](../FAQ.md#how-do-i-build-the-apisix-runtime-environment).
2. A WebSocket upstream. This example uses Postman's public echo service at `wss://ws.postman-echo.com/raw`; use a controlled test server if an external service is unsuitable for your environment.
3. A WebSocket client that can set custom headers, such as `websocat`.

## Create a WebSocket route

Reuse the resolved Admin API secret from the environment that starts APISIX:

```bash
admin_key="${ADMIN_KEY:?ADMIN_KEY is not set}"
```

If a local test configuration contains the actual key rather than an environment or secret reference, you can read that literal value with `admin_key="$(yq -r '.deployment.admin.admin_key[0].key' conf/config.yaml)"`. `yq` does not resolve `${{VARIABLE}}` templates or external secrets.

Create a Route that enables WebSocket proxying and authenticates the upgrade request:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/websocket-auth" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -H "Content-Type: application/json" \
  -d '{
    "uri": "/raw",
    "methods": ["GET"],
    "enable_websocket": true,
    "plugins": {
      "key-auth": {
        "hide_credentials": true
      }
    },
    "upstream": {
      "type": "roundrobin",
      "scheme": "https",
      "pass_host": "node",
      "tls": {
        "verify": true
      },
      "nodes": {
        "ws.postman-echo.com:443": 1
      }
    }
  }'
```

`enable_websocket` enables the protocol upgrade on the Route. The upstream
`scheme: https` corresponds to `wss://` for the proxied WebSocket connection.
`pass_host: node` sends the node hostname as the upstream `Host` and TLS server
name instead of forwarding the client's `127.0.0.1` host.

On an APISIX-Runtime build, `tls.verify: true` verifies the upstream certificate
using the CA certificates in `upstream.tls.ca_certs`, or the
`ssl_trusted_certificate` configured in `conf/config.yaml` when the Upstream does
not provide its own CA certificates. Keep verification enabled for authenticated
upstream TLS, and supply the appropriate private CA when the WebSocket service
does not use a publicly trusted certificate. See the
[Upstream section of the Admin API](../admin-api.md#upstream) for the current TLS
fields. A standard APISIX build without the required runtime modules cannot apply
these verification fields; use a controlled proxy or service-mesh hop that
verifies the upstream identity instead of sending sensitive traffic over an
unauthenticated upstream TLS connection.

## Create a Consumer credential

Create a Consumer and a separate `key-auth` credential:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/jack" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -H "Content-Type: application/json" \
  -d '{
    "username": "jack"
  }'
```

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/jack/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -H "Content-Type: application/json" \
  -d '{
    "id": "websocket-key",
    "plugins": {
      "key-auth": {
        "key": "this_is_the_key"
      }
    }
  }'
```

Use a generated secret delivered through your deployment's secret-management process in production. The fixed value above is only a local example.

## Test the handshake

Connecting without the configured header should fail with `401 Unauthorized`:

```shell
websocat -v ws://127.0.0.1:9080/raw
```

Connect again with the key in the configured header:

```shell
websocat -v -H='apikey: this_is_the_key' ws://127.0.0.1:9080/raw
```

After the server returns `101 Switching Protocols`, send a text message. The echo service should return the same message. Verify that the upstream does not receive the `apikey` header, that failed handshakes are logged without the raw credential, and that your connection-termination policy works when a credential is revoked.

The `key-auth` plugin also supports a query parameter and gives the header higher priority. If both sources are present, the plugin authenticates with the header; `hide_credentials` removes only that matched header, so the lower-priority query value can still reach the upstream. It also cannot prevent a query credential from first appearing in a URL. If the route must be header-only, reject credential-bearing query parameters at an earlier request-policy layer and test that behavior explicitly.
