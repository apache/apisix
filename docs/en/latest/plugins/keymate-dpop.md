---
title: keymate-dpop
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - DPoP
  - RFC 9449
  - Proof of Possession
  - Keymate
description: The keymate-dpop Plugin validates RFC 9449 DPoP (Demonstrating Proof of Possession) proofs for sender-constrained access tokens at the API gateway level.
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

The `keymate-dpop` Plugin validates [RFC 9449 DPoP (Demonstrating Proof of Possession)](https://datatracker.ietf.org/doc/html/rfc9449) proofs for sender-constrained access tokens at the API gateway level. Standard Bearer tokens can be stolen and replayed by any party. DPoP binds each access token to a cryptographic key held by the client, making stolen tokens useless without the corresponding private key.

Once enabled, the Plugin:

- Validates the DPoP proof JWT (`typ`, `alg`, `htm`, `htu`, `iat`, `ath`, `jti` claims)
- Verifies the DPoP proof signature using the embedded JWK public key
- Verifies the access token signature against the IdP's JWKS endpoint
- Validates the JWK Thumbprint binding (`cnf.jkt`) per [RFC 7638](https://datatracker.ietf.org/doc/html/rfc7638)
- Detects Bearer downgrade attacks (DPoP-bound token used with `Bearer` scheme)
- Enforces JTI replay protection with configurable cache backends (memory, Redis, or Infinispan)
- Converts `Authorization: DPoP <token>` to `Authorization: Bearer <token>` for upstream compatibility
- Strips the `DPoP` header and optionally injects a `DPoP-Thumbprint` header for upstream reference

The Plugin supports both JWT and opaque access tokens. For opaque tokens, set `enforce_introspection` to `true` to validate tokens via [RFC 7662 Token Introspection](https://datatracker.ietf.org/doc/html/rfc7662).

DPoP operates as a separate proof-of-possession layer on top of existing authentication. It complements plugins like `openid-connect` and `jwt-auth` rather than replacing them.

## Attributes

| Name | Type | Required | Default | Valid values | Description |
|------|------|----------|---------|-------------|-------------|
| allowed_algs | array[string] | False | ["ES256"] | ES256, ES384, ES512, RS256, RS384, RS512, PS256, PS384, PS512 | Allowed DPoP proof signing algorithms. |
| proof_max_age | integer | False | 120 | >= 1 | Maximum age of DPoP proof in seconds. |
| clock_skew_seconds | integer | False | 5 | >= 0 | Tolerance for `iat` claim validation in seconds. |
| verify_access_token | boolean | False | true | | Verify access token signature via JWKS. |
| discovery | string | False | | | OIDC discovery URL for JWKS endpoint resolution. |
| jwks_uri | string | False | | | Direct JWKS endpoint URL (alternative to `discovery`). |
| token_signing_algorithm | string | False | RS256 | RS256, RS384, RS512 | Expected access token signing algorithm. |
| jwks_cache_ttl | integer | False | 86400 | [60, 604800] | JWKS cache TTL in seconds. |
| introspection_endpoint | string | False | | | RFC 7662 token introspection endpoint URL. |
| introspection_client_id | string | False | | | Client ID for introspection authentication. |
| introspection_client_secret | string | False | | | Client secret for introspection authentication. |
| enforce_introspection | boolean | False | false | | Skip local token signature verification, use introspection directly. Requires `introspection_endpoint`. |
| introspection_cache_ttl | integer | False | 0 | [0, 3600] | Introspection response cache TTL in seconds. 0 disables caching. |
| replay_cache | object | False | | | JTI replay cache configuration. |
| replay_cache.type | string | False | memory | memory, redis, ispn | Replay cache backend. |
| replay_cache.fallback | string | False | memory | memory, bypass, reject | Fallback strategy when cache backend is unavailable. |
| replay_cache.ttl | integer | False | | >= 10 | JTI cache TTL in seconds. Defaults to `proof_max_age + clock_skew_seconds`. Must be >= `proof_max_age + clock_skew_seconds`. |
| replay_cache.redis.host | string | False | | | Redis host. Required when `replay_cache.type` is `redis`. |
| replay_cache.redis.port | integer | False | 6379 | [1, 65535] | Redis port. |
| replay_cache.redis.password | string | False | | | Redis password. |
| replay_cache.redis.timeout | integer | False | 2000 | >= 100 | Redis connection timeout in milliseconds. |
| replay_cache.ispn.endpoint | string | False | | | Infinispan REST v2 endpoint URL. Required when `replay_cache.type` is `ispn`. |
| replay_cache.ispn.cache_name | string | False | dpop-jti | | Infinispan cache name. |
| replay_cache.ispn.username | string | False | | | Infinispan username for HTTP Digest authentication. |
| replay_cache.ispn.password | string | False | | | Infinispan password for HTTP Digest authentication. |
| strict_htu | boolean | False | false | | Require exact `htu` claim match including scheme and host. When `false`, only the path is compared. |
| public_base_url | string | False | "" | | Public-facing base URL for `htu` validation. Required when `strict_htu` is `true`. |
| require_nonce | boolean | False | false | | Require server-issued nonce in DPoP proofs (not yet implemented). |
| send_thumbprint_header | boolean | False | true | | Inject `DPoP-Thumbprint` header for upstream services. |
| uri_allow | array[string] | False | [] | | Paths requiring DPoP enforcement. Empty array enforces on all paths. Supports exact match and wildcard `*`. |
| token_issuer | string | False | "" | | Expected token issuer (`iss` claim). Empty string skips validation. |

:::note

The Plugin requires the following `nginx_config.http.custom_lua_shared_dict` entries for cross-worker JTI replay detection and introspection caching:

```yaml
nginx_config:
  http:
    custom_lua_shared_dict:
      dpop_jti_cache: 10m
      dpop_intro_cache: 10m
```

Without these, the Plugin falls back to per-worker in-memory caches.

:::

## Examples

The examples below demonstrate how you can work with the `keymate-dpop` Plugin for different scenarios.

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Enable DPoP Validation with OIDC Discovery

The following example demonstrates how to enable DPoP proof validation on a Route using an OIDC discovery endpoint for JWKS resolution.

Create a Route with the `keymate-dpop` Plugin:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "uri": "/api/*",
    "upstream": {
      "type": "roundrobin",
      "nodes": { "127.0.0.1:8080": 1 }
    },
    "plugins": {
      "keymate-dpop": {
        "discovery": "https://keycloak.example.com/realms/myrealm/.well-known/openid-configuration",
        "allowed_algs": ["ES256"]
      }
    }
  }'
```

Send a valid DPoP request:

```shell
curl -i "http://127.0.0.1:9080/api/resource" \
  -H "Authorization: DPoP <access_token>" \
  -H "DPoP: <dpop_proof_jwt>"
```

The upstream service receives:

- `Authorization: Bearer <access_token>` (rewritten from DPoP scheme)
- `DPoP-Thumbprint: <jwk_thumbprint>` (injected by the Plugin)
- `DPoP` header is stripped

Send a request without a DPoP proof:

```shell
curl -i "http://127.0.0.1:9080/api/resource" \
  -H "Authorization: DPoP <access_token>"
```

An HTTP 401 response is returned with:

```
WWW-Authenticate: DPoP error="invalid_dpop_proof", error_description="missing DPoP proof header"
```

### Enable DPoP with Distributed Replay Protection

The following example enables Redis-backed JTI replay protection to prevent DPoP proof reuse across multiple gateway instances.

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "uri": "/api/*",
    "upstream": {
      "type": "roundrobin",
      "nodes": { "127.0.0.1:8080": 1 }
    },
    "plugins": {
      "keymate-dpop": {
        "discovery": "https://keycloak.example.com/realms/myrealm/.well-known/openid-configuration",
        "replay_cache": {
          "type": "redis",
          "fallback": "memory",
          "redis": { "host": "127.0.0.1", "port": 6379 }
        }
      }
    }
  }'
```

### Enable DPoP for Opaque Tokens with Introspection

The following example uses token introspection for opaque (non-JWT) access tokens.

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "uri": "/api/*",
    "upstream": {
      "type": "roundrobin",
      "nodes": { "127.0.0.1:8080": 1 }
    },
    "plugins": {
      "keymate-dpop": {
        "enforce_introspection": true,
        "introspection_endpoint": "https://keycloak.example.com/realms/myrealm/protocol/openid-connect/token/introspect",
        "introspection_client_id": "my-client",
        "introspection_client_secret": "my-secret",
        "introspection_cache_ttl": 300
      }
    }
  }'
```

### Selective DPoP Enforcement with uri_allow

The following example enforces DPoP only on specific paths, allowing other paths to pass through without DPoP validation.

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "uri": "/*",
    "upstream": {
      "type": "roundrobin",
      "nodes": { "127.0.0.1:8080": 1 }
    },
    "plugins": {
      "keymate-dpop": {
        "discovery": "https://keycloak.example.com/realms/myrealm/.well-known/openid-configuration",
        "uri_allow": ["/api/protected", "/api/admin/*"]
      }
    }
  }'
```

Requests to `/api/protected` and `/api/admin/*` require DPoP proofs. All other paths are forwarded without DPoP validation.

### Delete Plugin

To remove the `keymate-dpop` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "uri": "/api/*",
    "upstream": {
      "type": "roundrobin",
      "nodes": { "127.0.0.1:8080": 1 }
    },
    "plugins": {}
  }'
```

## FAQ

### What is the difference between DPoP and mTLS?

Both DPoP and mTLS provide proof of possession, but they operate at different layers. mTLS binds the TLS connection to a client certificate (transport layer), while DPoP binds individual access tokens to ephemeral keys (application layer). DPoP is more flexible: it works across TLS-terminating proxies, does not require certificate infrastructure, and allows per-token key rotation.

### Why does this Plugin run at priority 2601?

The `keymate-dpop` Plugin rewrites `Authorization: DPoP <token>` to `Authorization: Bearer <token>` before forwarding to upstream. It must run before other auth plugins (such as `openid-connect` at 2599 and `jwt-auth` at 2510) so they receive the expected `Bearer` scheme.

### Can I use DPoP with opaque (non-JWT) access tokens?

Yes. Set `enforce_introspection` to `true` and configure `introspection_endpoint`, `introspection_client_id`, and `introspection_client_secret`. The Plugin will call the introspection endpoint to validate the token and retrieve the `cnf.jkt` binding.

### Is there a WebAssembly (WASM) version?

Yes. A Go WASM version built with [proxy-wasm-go-sdk](https://github.com/proxy-wasm/proxy-wasm-go-sdk) v0.24.0 is available at [keymate-apisix-dpop-plugin](https://github.com/Keymate-io/keymate-apisix-dpop-plugin). You can configure it in `config.yaml`:

```yaml
wasm:
  plugins:
    - name: keymate-dpop-wasm
      priority: 2599
      file: /path/to/keymate-dpop.wasm
      http_request_phase: rewrite
```
