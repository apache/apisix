---
title: ldap-auth-advanced
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - LDAP Authentication
  - ldap-auth-advanced
description: The ldap-auth-advanced Plugin authenticates users against an LDAP directory using search-then-bind, so users do not need to be enumerated in APISIX.
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

<head>
  <link rel="canonical" href="https://docs.api7.ai/hub/ldap-auth-advanced" />
</head>

## Description

The `ldap-auth-advanced` Plugin adds LDAP authentication to a Route or a Service. Unlike [`ldap-auth`](./ldap-auth.md), which binds with a DN assembled from the Consumer configuration, this Plugin *searches* the directory for the user first, then binds as the entry it found. Users therefore do not need to be enumerated in APISIX.

On each request the Plugin:

1. Reads the credentials from the `Proxy-Authorization` header, falling back to `Authorization`.
2. Searches `base_dn` for the entry whose `attribute` matches the supplied username, then binds as that entry with the supplied password.
3. Attaches a matching [Consumer](../terminology/consumer.md), unless `consumer_required` is `false`.

The credential header uses the scheme word given by `header_type`, which defaults to `ldap` rather than `basic`, so the default expects `Authorization: ldap <base64(username:password)>`. Set `header_type` to `basic` to accept ordinary [basic access authentication](https://en.wikipedia.org/wiki/Basic_access_authentication) instead.

The Plugin distinguishes two failure modes, so an outage is never reported as a rejected credential:

| Status | Cause |
|--------|-------|
| `401` | Missing, malformed, or rejected credentials; a username matching more than one entry; or `consumer_required` is `true` and no Consumer matches. Returned with a `WWW-Authenticate` header. |
| `500` | The directory is unreachable or the `bind_dn` credentials were rejected. |

This Plugin uses [lua-resty-ldap](https://github.com/api7/lua-resty-ldap) to connect to the LDAP server.

## Attributes

For Consumer:

| Name | Type | Required | Default | Valid values | Description |
|------|------|----------|---------|--------------|-------------|
| user_dn | string | True | | | DN of the LDAP user bound to this Consumer, for example `cn=Jane Doe,ou=users,dc=example,dc=org`. This field supports storing the value in Secret Manager using the [APISIX Secret](../terminology/secret.md) resource. |

For Route:

| Name | Type | Required | Default | Valid values | Description |
|------|------|----------|---------|--------------|-------------|
| ldap_uri | string | True | | | Address of the LDAP server as `host` or `host:port`. When the port is omitted, `636` is used if `use_ldaps` is enabled and `389` otherwise. |
| base_dn | string | True | | | DN of the subtree searched for the user, for example `ou=users,dc=example,dc=org`. |
| attribute | string | False | cn | | User attribute matched against the supplied username, for example `uid` or `sAMAccountName`. |
| bind_dn | string | False | | | DN used to bind before searching for the user. When unset, the search binds anonymously. |
| ldap_password | string | False | | | Password for `bind_dn`. Required when `bind_dn` is set. The password is encrypted with AES before being stored in etcd. |
| use_ldaps | boolean | False | false | | If true, connect over LDAPS. Mutually exclusive with `use_starttls`. |
| use_starttls | boolean | False | false | | If true, upgrade the connection with StartTLS. Mutually exclusive with `use_ldaps`. |
| ssl_verify | boolean | False | true | | If true, verify the LDAP server's certificate. Requires `ssl_trusted_certificate` to be set in `config.yaml`, and the host in `ldap_uri` to match the host in the server certificate. |
| timeout | integer | False | 10000 | [1, 60000] | Socket timeout in milliseconds. |
| keepalive | boolean | False | true | | If true, return the connection to the pool for reuse instead of closing it. |
| keepalive_timeout | integer | False | 60000 | >= 1000 | Idle time in milliseconds after which a pooled connection is closed. |
| keepalive_pool_size | integer | False | 5 | >= 1 | Maximum number of connections kept in the pool. |
| keepalive_pool_name | string | False | | | Name of the connection pool. Set this to keep connections that use different credentials in separate pools. |
| size_limit | integer | False | 2 | >= 2 | Maximum number of entries the user search may return. The login attribute is expected to be unique, so more than one match is treated as ambiguous and rejected. |
| time_limit | integer | False | 5 | >= 0 | Time limit of the search in seconds. `0` uses the server default. |
| consumer_required | boolean | False | true | | If true, reject the request with `401` when no Consumer matches the authenticated user. |
| header_type | string | False | ldap | ["ldap", "basic"] | Scheme word expected in the credential header. |
| realm | string | False | ldap | | Realm in the [`WWW-Authenticate`](https://datatracker.ietf.org/doc/html/rfc7235#section-4.1) response header returned with a `401 Unauthorized` response. |

## Examples

The examples below assume an LDAP directory under `dc=example,dc=org` that contains a user `Jane Doe` with `uid` of `jdoe` and password `janesecret`.

:::note

You can fetch the `admin_key` from `config.yaml` and save it to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Authenticate Against an LDAP Directory

The following example shows the minimum configuration: search `base_dn` for a matching `uid`, then bind as that user.

Create a Route with `ldap-auth-advanced`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "ldap-auth-advanced-route",
    "uri": "/anything",
    "plugins": {
      "ldap-auth-advanced": {
        "ldap_uri": "127.0.0.1:1389",
        "base_dn": "ou=users,dc=example,dc=org",
        "attribute": "uid",
        "consumer_required": false
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

Send a request with valid credentials:

```shell
curl -i "http://127.0.0.1:9080/anything" \
  -H "Authorization: ldap $(echo -n 'jdoe:janesecret' | base64)"
```

You should receive an `HTTP/1.1 200 OK` response.

Send a request without credentials:

```shell
curl -i "http://127.0.0.1:9080/anything"
```

You should receive an `HTTP/1.1 401 Unauthorized` response with the following body:

```text
{"message":"Authorization required"}
```

The response also carries the challenge built from `realm`:

```text
WWW-Authenticate: ldap realm="ldap"
```

A request with a wrong password is rejected the same way.

If your directory does not allow anonymous searches, bind with a service account by adding `bind_dn` and `ldap_password`. The user is still authenticated with their own bind:

```json
{
  "ldap-auth-advanced": {
    "ldap_uri": "127.0.0.1:1389",
    "base_dn": "ou=users,dc=example,dc=org",
    "attribute": "uid",
    "bind_dn": "cn=admin,dc=example,dc=org",
    "ldap_password": "adminpassword",
    "consumer_required": false
  }
}
```

To accept standard basic authentication instead of the `ldap` scheme, set `header_type` to `basic`. Clients can then use `curl -u jdoe:janesecret`.

### Map LDAP Identities to Consumers

Associating an LDAP identity with a Consumer lets APISIX apply per-Consumer configuration, such as rate limits, and adds the `X-Consumer-Username` header to the Upstream request. A Consumer is bound to one LDAP user with `user_dn`.

Create a Consumer bound to a user:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "jane",
    "plugins": {
      "ldap-auth-advanced": {
        "user_dn": "cn=Jane Doe,ou=users,dc=example,dc=org"
      }
    }
  }'
```

Update the Route to require a Consumer by removing `consumer_required`, which defaults to `true`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "ldap-auth-advanced-route",
    "uri": "/anything",
    "plugins": {
      "ldap-auth-advanced": {
        "ldap_uri": "127.0.0.1:1389",
        "base_dn": "ou=users,dc=example,dc=org",
        "attribute": "uid"
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

Send a request as `jdoe`:

```shell
curl "http://127.0.0.1:9080/anything" \
  -H "Authorization: ldap $(echo -n 'jdoe:janesecret' | base64)"
```

You should see the Consumer identified in the Upstream request:

```json
{
  "headers": {
    "X-Consumer-Username": "jane",
    ...
  },
  ...
}
```

Users matching no Consumer are rejected with `401`, unless `consumer_required` is set to `false`.

### Connect over LDAPS

Set `use_ldaps` to connect over LDAPS, or `use_starttls` to upgrade a plaintext connection. The two are mutually exclusive and the configuration is rejected if both are enabled.

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "ldap-auth-advanced-route",
    "uri": "/anything",
    "plugins": {
      "ldap-auth-advanced": {
        "ldap_uri": "ldap.example.org",
        "use_ldaps": true,
        "ssl_verify": true,
        "base_dn": "ou=users,dc=example,dc=org",
        "attribute": "uid",
        "consumer_required": false
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

When the port is omitted from `ldap_uri`, `636` is used with `use_ldaps` and `389` otherwise.

`ssl_verify` is enabled by default. Verification requires `ssl_trusted_certificate` in `config.yaml` to point at the CA that signed the LDAP server certificate, and the host in `ldap_uri` to match the certificate. A certificate that cannot be verified fails the request with `500`.

## Delete Plugin

To remove the `ldap-auth-advanced` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/ldap-auth-advanced-route" -X PATCH \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "plugins": {}
  }'
```
