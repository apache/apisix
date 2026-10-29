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

APISIX needs [APISIX Runtime](../FAQ.md#how-do-i-build-the-apisix-runtime-environment) for this Plugin: the keys are kept in a shared memory zone of the main-level `lua {}` block, which is common to the HTTP and the Stream subsystems. The business TLS listeners only use them with an APISIX Runtime that takes over their session ticket keys, see [Business TLS Listeners](#business-tls-listeners).

## Local Policy

The local configuration decides whether the shared keys are used and where they come from. These attributes are not part of the plugin metadata and cannot be changed through the Admin API.

```yaml title="./conf/config.yaml"
plugin_attr:
  ssl-session-ticket:
    enabled: false
    key_source: generated
    generated:
      rotation_interval: 3600
      max_keys: 19
```

| Name                        | Type    | Required | Default   | Valid values        | Description |
|-----------------------------|---------|----------|-----------|---------------------|-------------|
| enabled                     | boolean | False    | false     |                     | If true, the keys are published for the business TLS listeners. The keys submitted through the Admin API do not enable the feature by themselves. |
| key_source                  | string  | False    | generated | generated, external | `generated`: APISIX generates and rotates the keys, see [Generated Keys](#generated-keys), and the Admin API rejects any write to them. `external`: you submit the complete set of keys through the Admin API. |
| generated.rotation_interval | integer | False    | 3600      | >= 60               | Seconds between two new keys issuing tickets. Only used with `generated`. |
| generated.max_keys          | integer | False    | 19        | [1, 256]            | Number of keys kept, including the one issuing tickets. Only used with `generated`. |

APISIX checks these attributes when it starts. Configure them the same way on all the nodes that apply them, see [Policy Consistency](#policy-consistency). A change of the local configuration takes effect after a reload, like any other change of `config.yaml`.

| Deployment                                 | Local policy | Keys |
|--------------------------------------------|--------------|------|
| `traditional` and `control_plane` with etcd | Applied: generate the keys, or accept the external ones through the Admin API, and keep the metadata in line with `enabled` and `key_source`. | Used by the node. |
| `data_plane`                               | Ignored. | Used as the nodes applying the policy publish them. |
| Standalone (YAML, JSON or API-driven)      | Only `external` keys, and `enabled` decides whether they are used. `enabled: true` with `key_source: generated` fails on startup. | Taken from the configuration, see [Standalone Mode](#standalone-mode). |
| Stream only (`proxy_mode: stream`)         | Not applied: the generator runs in the privileged agent of the HTTP subsystem. | Used as the other nodes publish them. |

## Business TLS Listeners

Every worker process applies the published keys to the TLS listeners of the business traffic, independently in the HTTP and the Stream subsystems:

* the HTTPS listeners of `apisix.ssl.listen`, HTTP/3 included,
* the Stream listeners of `apisix.stream_proxy.tcp` with `tls: true`, including the internal server that terminates TLS on a listen that also has `tls_passthrough: true`.

The Admin API, the Control API, the Status API, the Prometheus export server, the TLS passthrough of Stream, plain TCP and UDP, and the TLS connections to the upstreams keep their own configuration.

A worker applies a new set of keys within a second, then aligns each new connection with it when the connection reaches its ClientHello, without waiting for handshakes to happen. A listener issues stateless tickets only once the complete set of keys is in place, and stops issuing and accepting them before the keys are removed. Changing the keys closes no connection.

The local switch `apisix.ssl.ssl_session_tickets` decides whether the business listeners of a node use the shared keys. It is true unless it is set to false. When it is false, or when there is no key to use (the Plugin is not enabled, the keys are disabled, empty or cannot be loaded), the business listeners issue no stateless ticket:

* With TLS 1.2, a client then only resumes a session through the session cache of the node, which the HTTPS listeners have (`shared:SSL:20m`, 10 minutes) and the Stream listeners do not.
* With TLS 1.3, an HTTPS listener still sends the stateful tickets of its session cache, which only resume on the same node.

This takeover needs an APISIX Runtime whose `apisix-nginx-module` provides it. With an older APISIX Runtime, the listeners keep the behavior of the previous versions: the keys are published, but the TLS listeners do not use them and the Control API reports `module_not_active`.

## Generated Keys

With `enabled: true` and `key_source: generated`, the privileged agent of every node applying the local policy checks the keys every few seconds:

* Without keys, it generates the first one, from a cryptographically secure random generator.
* When `rotation_interval` seconds have passed since the keys were last generated, it adds a new key in front, which issues the tickets from then on, and removes the oldest keys beyond `max_keys`. With the defaults, a key issues tickets for an hour and then decrypts them for 18 more hours.
* The time of the last generation is saved with the keys: restarting a node does not restart the period, and a node that comes back after a long stop rotates the keys once, not once per missed period.
* Lowering `max_keys` removes the keys beyond it at once.

The nodes write the keys with an etcd transaction against the revision they have read: when several nodes are due at the same time, only one of them writes and the others read its keys. If a node fails to generate or to encrypt a key, it writes nothing and the keys in use stay as they are.

The nodes applying the local policy also keep the metadata in line with it:

* With `enabled: false`, the keys are marked disabled and stay in the metadata: the TLS listeners stop using them. Enabling again resumes with them, and the next rotation replaces them over time.
* Switching to `external` replaces the generated keys with an empty set, waiting for yours. Switching to `generated` replaces the external keys with a new generated one. Keys of one source are never used as keys of the other.

A node that cannot read the current keys, for example because its `apisix.data_encryption.keyring` differs, never overwrites them; the Control API reports the error.

### Policy Consistency

Each node applying the local policy registers a fingerprint of it in etcd, under `/apisix/ssl_session_ticket/policy/`, with a lease that ends about 30 seconds after the node stops. As long as the registered nodes do not all have the same policy, they all stop generating keys and rewriting the metadata, and the Admin API rejects writes to the metadata with `409`. The Control API reports `conflict` in `generator.state`, and the error log tells why. Everything resumes once all the nodes have the same configuration. Changing the policy with a rolling restart therefore pauses the rotation for a while; the published keys stay in use.

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
| `key_source: generated`                   | `409`          | APISIX generates the keys. Switch to `external` to manage them through the Admin API. |

* `PUT` replaces the whole set. The same keys in the same order write nothing and do not create a new revision, so a declarative tool such as ADC may submit the same set again and again.
* The request body only accepts `keys`. Any other field, such as `enabled`, `key_source`, `origin`, `id`, a reference or a per-key time, is rejected. So are a key that is not valid base64, a key that does not decode to 80 bytes, a duplicated key, two keys with the same 16-byte name and more than 256 keys. An invalid request is rejected as a whole: nothing is written and the saved keys stay as they are.
* The keys have no TTL, the `ttl` argument is rejected.
* Each write is atomic against the revision that the request has read. When another writer changes the keys in between, the request fails with `409` and nothing is written; retry it.
* Writes fail with `409` as long as the nodes applying the local policy do not all have the same one, see [Policy Consistency](#policy-consistency).
* APISIX adds an `origin` object to the stored metadata: the source of the keys, whether they are disabled by the local policy, and a fingerprint of that policy. You cannot set it.
* No response contains the keys, neither in clear text nor encrypted: they are replaced with `<redacted>`. Keep the keys yourself, a `GET` result cannot be submitted again.
* When `apisix.data_encryption.enable_encrypt_fields` is true, the keys are encrypted with `apisix.data_encryption.keyring` before they are saved to etcd. If the encryption fails, the request fails and nothing is written.

## Example Usage

### Use Generated Keys

Enable the generated keys in the local configuration of the nodes that apply the local policy, then reload APISIX:

```yaml title="./conf/config.yaml"
plugin_attr:
  ssl-session-ticket:
    enabled: true
```

Check that the keys are there, on any node:

```shell
curl http://127.0.0.1:9090/v1/tls_session_ticket
```

The response reports `"source": "generated"` and the number of keys, and on the nodes generating them, a `generator` object with `"state": "ok"`.

### Use External Keys

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

The metadata only shows what is saved, not what the nodes use. The Control API of each node reports its own state in [`GET /v1/tls_session_ticket`](../control-api.md#get-v1tls_session_ticket): the source and the revision of the keys, the number of keys, the local version and the time it was published, how many worker processes of each subsystem have applied it, the state of the generator on the nodes applying the local policy, and the security warnings. It never returns the keys.

* `ok`: every business TLS listener of the node uses the current keys.
* `off`: every business TLS listener of the node has stopped using shared keys, because of the local switch (`local_switch_off`), the local policy (`disabled_by_policy`), or because there is no key (`empty_keys`, also when the Plugin is not enabled). A node without any business TLS listener is `off` as well.
* `degraded`: some worker has not applied the current keys yet (`worker_lag`), or something failed (`invalid_state`, `module_not_active`, `apply_failed`). A listener that failed to apply the keys uses no shared key, and the node stays `degraded` until the failure is gone: `last_apply_error` tells why.

To check that new keys are in use, or that disabled ones no longer are, query every node and compare `source_version` with the revision of the metadata, then check `status` and `fully_applied`. A worker of a previous configuration generation that is still running counts too, in `draining`.

A node that cannot reach etcd keeps the keys it has, without any time limit: nothing revokes the keys of a node that stops receiving updates. To withdraw keys urgently, disable or replace them, check that every node reports it, and stop or isolate the nodes that do not.

## Upgrade Notes

With an APISIX Runtime that takes over the session ticket keys:

* `apisix.ssl.ssl_session_tickets` changes meaning for the business HTTPS listeners. `true` used to turn on the native session tickets of NGINX, with random keys of each node; it now allows the shared keys, and without them these listeners issue no stateless ticket. Unset, it now means true: with no published keys, the HTTPS listeners still issue no stateless ticket, as with the previous default.
* The Stream TLS listeners used the native session tickets of NGINX, with random keys of each worker process. They now only issue tickets with the shared keys: without keys, Stream TLS sessions are not resumed.
* The Admin API is not affected: it still uses the native session tickets of NGINX only when `apisix.ssl.ssl_session_tickets` is explicitly true.
* A configuration that had the session tickets on does not get them back by itself: enable the Plugin and provide keys, see [Example Usage](#example-usage).

## Security

* A key decrypts every ticket that it has issued. With TLS 1.2, whoever obtains a key can also decrypt the recorded traffic of the sessions resumed with its tickets. Generate the keys with a secure random generator, rotate them, and restrict the access to the Admin API and to etcd.
* The same keys on all the nodes widen the impact of a single compromised node. This is why `enabled` defaults to false. A node keeps using the keys it has until it receives other ones, see [Status](#status).
* When `apisix.data_encryption.enable_encrypt_fields` is false, or `apisix.data_encryption.keyring` still contains the public example keys of the default configuration, APISIX logs a warning and the Control API reports `encryption_disabled` or `default_keyring` in `warnings`. The keys still work, but configure a private keyring to protect them in etcd.
* The keys never appear in the responses of the Admin API, in the plugin metadata dumps of the Control API, or in the error log, even when a request is invalid or is not valid JSON.
