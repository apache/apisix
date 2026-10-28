---
title: ssl-session-ticket
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - ssl-session-ticket
  - TLS session ticket
description: The ssl-session-ticket Plugin shares the TLS session ticket keys of the business TLS listeners across the APISIX nodes.
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

With TLS session tickets, a client resumes a TLS session without a full handshake. The server encrypts the session into a ticket that the client keeps, so the client can resume on any node that holds the same ticket key. The `ssl-session-ticket` Plugin provides one ordered set of ticket keys to all the APISIX nodes that share a configuration: the first key issues tickets, and every key of the set decrypts them.

The keys are meant for the TLS listeners that carry the business traffic: HTTPS, and the Stream proxies that terminate TLS. The Admin API, the Control API and the other management listeners keep their own TLS configuration.

The Plugin is a global system Plugin. It is configured only through its plugin metadata, has no request phase, and cannot be bound to a Route, a Service or a Consumer. It is enabled by default in both `plugins` and `stream_plugins`, so that a Stream-only deployment receives the keys too.

APISIX needs [APISIX Runtime](../FAQ.md#how-do-i-build-the-apisix-runtime-environment) for this Plugin: the keys are kept in a shared memory zone of the main-level `lua {}` block, which is common to the HTTP and the Stream subsystems.

## Local Policy

The local configuration decides whether the shared keys are used and where they come from. These attributes are not part of the plugin metadata and cannot be changed through the Admin API.

```yaml title="./conf/config.yaml"
plugin_attr:
  ssl-session-ticket:
    enabled: false
    key_source: generated
```

| Name       | Type    | Required | Default   | Valid values          | Description |
|------------|---------|----------|-----------|-----------------------|-------------|
| enabled    | boolean | False    | false     |                       | If true, the keys are published for the business TLS listeners. The keys submitted through the Admin API do not enable the feature by themselves. |
| key_source | string  | False    | generated | generated, external   | `generated`: APISIX maintains the keys and the Admin API rejects any write to them. `external`: you submit the complete set of keys through the Admin API. |

The `traditional` and `control_plane` nodes apply this policy, and `data_plane` nodes ignore it. Configure it the same way on all the nodes that apply it. A change of the local configuration takes effect after a reload, like any other change of `config.yaml`.

In standalone mode (YAML, JSON or API-driven), only `external` keys are supported, see [Standalone Mode](#standalone-mode).

## Plugin Metadata

With `key_source: external`, submit the complete set of keys to the plugin metadata of `ssl-session-ticket`:

| Name | Type          | Required | Description |
|------|---------------|----------|-------------|
| keys | array[string] | True     | The complete ordered set of keys. Each key is the base64 encoding of 80 random bytes. The first key issues tickets, all the keys decrypt them. At most 256 keys. An empty array means that there is no shared key. |

The 80 bytes of a key are a 16-byte key name, a 32-byte HMAC key and a 32-byte AES key, in the layout of NGINX [ssl_session_ticket_key](https://nginx.org/en/docs/http/ngx_http_ssl_module.html#ssl_session_ticket_key) files. Generate each key with a cryptographically secure random generator, for example:

```shell
openssl rand 80 | base64 -w 0
```

The Admin API applies these rules to the `ssl-session-ticket` metadata:

| Local policy                              | PUT and DELETE | Effect |
|-------------------------------------------|----------------|--------|
| `enabled: false`, `key_source: external`  | Allowed        | The keys are saved, marked disabled, and not used. |
| `enabled: true`, `key_source: external`   | Allowed        | The keys are used exactly as given: APISIX does not add, expire, rotate or remove any of them. |
| `key_source: generated`                   | `409`          | APISIX maintains the keys. Switch to `external` to manage them through the Admin API. |

* `PUT` replaces the whole set. The same keys in the same order write nothing and do not create a new revision, so a declarative tool such as ADC may submit the same set again and again.
* The request body only accepts `keys`. Any other field, such as `enabled`, `key_source`, `origin`, `id`, a reference or a per-key time, is rejected. So are a key that is not valid base64, a key that does not decode to 80 bytes, a duplicated key, two keys with the same 16-byte name and more than 256 keys. An invalid request is rejected as a whole: nothing is written and the saved keys stay as they are.
* The keys have no TTL, the `ttl` argument is rejected.
* Each write is atomic against the revision that the request has read. When another writer changes the keys in between, the request fails with `409` and nothing is written; retry it.
* APISIX adds an `origin` object to the stored metadata: the source of the keys, whether they are disabled by the local policy, and a fingerprint of that policy. You cannot set it.
* No response contains the keys, neither in clear text nor encrypted: they are replaced with `<redacted>`. Keep the keys yourself, a `GET` result cannot be submitted again.
* When `apisix.data_encryption.enable_encrypt_fields` is true, the keys are encrypted with `apisix.data_encryption.keyring` before they are saved to etcd. If the encryption fails, the request fails and nothing is written.

## Example Usage

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

Select the external keys in the local configuration of the nodes that apply the local policy, then reload APISIX:

```yaml title="./conf/config.yaml"
plugin_attr:
  ssl-session-ticket:
    enabled: true
    key_source: external
```

Submit a first key:

```shell
K1=$(openssl rand 80 | base64 -w 0)

curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/ssl-session-ticket \
  -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "keys": ["'"$K1"'"]
}'
```

```json
{
  "key": "/apisix/plugin_metadata/ssl-session-ticket",
  "value": {
    "id": "ssl-session-ticket",
    "keys": ["<redacted>"],
    "origin": {
      "source": "external",
      "disabled": false,
      "policy": "1d6de6a6"
    }
  }
}
```

To rotate, put a new key first and keep the previous one, so that the tickets issued with it can still be resumed:

```shell
K2=$(openssl rand 80 | base64 -w 0)

curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/ssl-session-ticket \
  -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "keys": ["'"$K2"'", "'"$K1"'"]
}'
```

The next rotation submits `[K3, K2]`, and so on. Each request carries the complete set. To distribute a new key before it issues tickets, submit `[K1, K2]` first, then `[K2, K1]`.

To remove the external keys, submit an empty array or delete the metadata:

```shell
curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/ssl-session-ticket \
  -H "X-API-KEY: $admin_key" -X DELETE
```

## Standalone Mode

A standalone configuration carries the keys in the plugin metadata, without `origin`:

```yaml title="./conf/apisix.yaml"
plugin_metadata:
  - id: ssl-session-ticket
    keys:
      - <base64 of 80 random bytes>
#END
```

The keys are external keys and the local `enabled` attribute decides whether they are used. The configuration version orders the changes. A record with `origin.source: generated` is not valid in standalone mode.

## Status

The metadata only shows what is saved, not what the nodes use. The Control API of each node reports its own state in [`GET /v1/tls_session_ticket`](../control-api.md#get-v1tls_session_ticket): the source and the revision of the keys, the number of keys, the local version and the time it was published, and the security warnings. It never returns the keys.

## Security

* A key decrypts every ticket that it has issued. With TLS 1.2, whoever obtains a key can also decrypt the recorded traffic of the sessions resumed with its tickets. Generate the keys with a secure random generator, rotate them, and restrict the access to the Admin API and to etcd.
* The same keys on all the nodes widen the impact of a single compromised node. This is why `enabled` defaults to false.
* When `apisix.data_encryption.enable_encrypt_fields` is false, or `apisix.data_encryption.keyring` still contains the public example keys of the default configuration, APISIX logs a warning and the Control API reports `encryption_disabled` or `default_keyring` in `warnings`. The keys still work, but configure a private keyring to protect them in etcd.
* The keys never appear in the responses of the Admin API, in the plugin metadata dumps of the Control API, or in the error log, even when a request is invalid or is not valid JSON.
