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

## Description

Secrets refer to any sensitive information required during the running process of APISIX, which may be part of the core configuration (such as the etcd's password) or some sensitive information in the plugin. Common types of Secrets in APISIX include:

- username, the password for some components (etcd, Redis, Kafka, etc.)
- the private key of the certificate
- API key
- Sensitive plugin configuration fields, typically used for authentication, hashing, signing, or encryption

APISIX Secret allows users to store secrets through some secrets management services (Vault, etc.) in APISIX, and read them according to the key when using them to ensure that **Secrets do not exist in plain text throughout the platform**.

Its working principle is shown in the figure:
![secret](../../../assets/images/secret.png)

APISIX currently supports storing secrets in the following ways:

- [Environment Variables](#use-environment-variables-to-manage-secrets)
- [HashiCorp Vault](#use-vault-to-manage-secrets)

You can use APISIX Secret functions by specifying format variables in the consumer configuration of the following plugins, such as `key-auth`.

:::note

If a key-value pair `key: "$ENV://ABC"` is configured in APISIX and the value of `$ENV://ABC` is unassigned in the environment variable, `$ENV://ABC` will be interpreted as a string literal, instead of `nil`.

:::

## Use environment variables to manage secrets

Using environment variables to manage secrets means that you can save key information in environment variables, and refer to environment variables through variables in a specific format when configuring plugins. APISIX supports referencing system environment variables and environment variables configured through the Nginx `env` directive.

### Usage

```
$ENV://$env_name/$sub_key
```

- env_name: environment variable name
- sub_key: get the value of a property when the value of the environment variable is a JSON string

 If the value of the environment variable is of type string, such as:

```
export JACK_AUTH_KEY=abc
```

It can be referenced as follows:

```
$ENV://JACK_AUTH_KEY
```

If the value of the environment variable is a JSON string like:

```
export JACK={"auth-key":"abc","openid-key": "def"}
```

It can be referenced as follows:

```
# Get the auth-key of the environment variable JACK
$ENV://JACK/auth-key

# Get the openid-key of the environment variable JACK
$ENV://JACK/openid-key
```

### Example: use in key-auth plugin

Step 1: Create environment variables before the APISIX instance starts

```
export JACK_AUTH_KEY=abc
```

Step 2: Reference the environment variable in the `key-auth` plugin

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/consumers \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "username": "jack",
    "plugins": {
        "key-auth": {
            "key": "$ENV://JACK_AUTH_KEY"
        }
    }
}'
```

Through the above steps, the `key` configuration in the `key-auth` plugin can be saved in the environment variable instead of being displayed in plain text when configuring the plugin.

## Use Vault to manage secrets

Using Vault to manage secrets means that you can store secrets information in the Vault service and refer to it through variables in a specific format when configuring plugins. APISIX currently supports [Vault KV engine version V1](https://developer.hashicorp.com/vault/docs/secrets/kv/kv-v1).

### Usage

```
$secret://$manager/$id/$secret_name/$key
```

- manager: secrets management service, could be the Vault, AWS, etc.
- id: APISIX Secrets resource ID, which needs to be consistent with the one specified when adding the APISIX Secrets resource
- secret_name: the secret name in the secrets management service
- key: the key corresponding to the secret in the secrets management service

### Example: use in key-auth plugin

Step 1: Create the corresponding key in the Vault, you can use the following command:

```shell
vault kv put apisix/jack auth-key=value
```

Step 2: Add APISIX Secrets resources through the Admin API, configure the Vault address and other connection information:

```shell
curl http://127.0.0.1:9180/apisix/admin/secrets/vault/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "https://127.0.0.1:8200"，
    "prefix": "apisix",
    "token": "root"
}'
```

If you use APISIX Standalone mode, you can add the following configuration in `apisix.yaml` configuration file:

```yaml
secrets:
  - id: vault/1
    prefix: apisix
    token: root
    uri: 127.0.0.1:8200
```

Step 3: Reference the APISIX Secrets resource in the `key-auth` plugin and fill in the key information:

```shell
curl http://127.0.0.1:9180/apisix/admin/consumers \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "username": "jack",
    "plugins": {
        "key-auth": {
            "key": "$secret://vault/1/jack/auth-key"
        }
    }
}'
```

Through the above two steps, when the user request hits the `key-auth` plugin, the real value of the key in the Vault will be obtained through the APISIX Secret component.
