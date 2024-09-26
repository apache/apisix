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
- [HashiCorp Vault](#use-hashicorp-vault-to-manage-secrets)
- [AWS Secrets Manager](#use-aws-secrets-manager-to-manage-secrets)
- [GCP Secrets Manager](#use-gcp-secrets-manager-to-manage-secrets)

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

## Use HashiCorp Vault to manage secrets

Using HashiCorp Vault to manage secrets means that you can store secrets information in the Vault service and refer to it through variables in a specific format when configuring plugins. APISIX currently supports [Vault KV engine version V1](https://developer.hashicorp.com/vault/docs/secrets/kv/kv-v1).

### Usage

```
$secret://$manager/$id/$secret_name/$key
```

- manager: secrets management service, could be the HashiCorp Vault, AWS, etc.
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

:::tip

It now supports the use of the [`namespace` field](../admin-api.md#request-body-parameters-11) to set the multi-tenant namespace concepts supported by [HashiCorp Vault Enterprise](https://developer.hashicorp.com/vault/docs/enterprise/namespaces#vault-api-and-namespaces) and HCP Vault.

:::

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

## Use AWS Secrets Manager to manage secrets

Managing secrets with AWS Secrets Manager is a secure and convenient way to store and manage sensitive information. This method allows you to save secret information in AWS Secrets Manager and reference these secrets in a specific format when configuring APISIX plugins.

APISIX currently supports two authentication methods: using [long-term credentials](https://docs.aws.amazon.com/sdkref/latest/guide/access-iam-users.html) and [short-term credentials](https://docs.aws.amazon.com/sdkref/latest/guide/access-temp-idc.html).

### Usage

```
$secret://$manager/$id/$secret_name/$key
```

- manager: secrets management service, could be the HashiCorp Vault, AWS, etc.
- id: APISIX Secrets resource ID, which needs to be consistent with the one specified when adding the APISIX Secrets resource
- secret_name: the secret name in the secrets management service
- key: get the value of a property when the value of the secret is a JSON string

### Required Parameters

| Name | Required | Default Value | Description |
| --- | --- | --- | --- |
| access_key_id | True |  | AWS Access Key ID |
| secret_access_key | True |  | AWS Secret Access Key |
| session_token | False |  | Temporary access credential information |
| region | False | us-east-1 | AWS Region |
| endpoint_url | False | https://secretsmanager.{region}.amazonaws.com | AWS Secret Manager URL |

### Example: use in key-auth plugin

Here, we use the key-auth plugin as an example to demonstrate how to manage secrets through AWS Secrets Manager.

Step 1: Create the corresponding key in the AWS secrets manager. Here, [localstack](https://www.localstack.cloud/) is used for as the example environment, and you can use the following command:

```shell
docker exec -i localstack sh -c "awslocal secretsmanager create-secret --name jack --description 'APISIX Secret' --secret-string '{\"auth-key\":\"value\"}'"
```

Step 2: Add APISIX Secrets resources through the Admin API, configure the connection information such as the address of AWS Secrets Manager.

You can store the critical key information in environment variables to ensure the configuration information is secure, and reference it where it is used:

```shell
export AWS_ACCESS_KEY_ID=<access_key_id>
export AWS_SECRET_ACCESS_KEY=<secrets_access_key>
export AWS_SESSION_TOKEN=<token>
export AWS_REGION=<aws-region>
```

Alternatively, you can also specify all the information directly in the configuration:

```shell
curl http://127.0.0.1:9180/apisix/admin/secrets/aws/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "endpoint_url": "http://127.0.0.1:4566",
    "region": "us-east-1",
    "access_key_id": "access",
    "secret_access_key": "secret",
    "session_token": "token"
}'
```

If you use APISIX Standalone mode, you can add the following configuration in `apisix.yaml` configuration file:

```yaml
secrets:
  - id: aws/1
    endpoint_url: http://127.0.0.1:4566
    region: us-east-1
    access_key_id: access
    secret_access_key: secret
    session_token: token
```

Step 3: Reference the APISIX Secrets resource in the `key-auth` plugin and fill in the key information:

```shell
curl http://127.0.0.1:9180/apisix/admin/consumers \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "username": "jack",
    "plugins": {
        "key-auth": {
            "key": "$secret://aws/1/jack/auth-key"
        }
    }
}'
```

Through the above two steps, when the user request hits the `key-auth` plugin, the real value of the key in the Vault will be obtained through the APISIX Secret component.

### Verification

You can verify this with the following command:

```shell
#Replace the following your_route with the actual route path.
curl -i http://127.0.0.1:9080/your_route -H 'apikey: value'
```

This will verify whether the `key-auth` plugin is correctly using the key from AWS Secrets Manager.

## Use GCP Secrets Manager to manage secrets

Using the GCP Secrets Manager to manage secrets means you can store the secret information in the GCP service, and reference it using a specific format of variables when configuring plugins. APISIX currently supports integration with the GCP Secrets Manager, and the supported authentication method is [OAuth 2.0](https://developers.google.com/identity/protocols/oauth2).

### Reference Format

```
$secret://$manager/$id/$secret_name/$key
```

The reference format is the same as before:

- manager: secrets management service, could be the HashiCorp Vault, AWS, GCP etc.
- id: APISIX Secrets resource ID, which needs to be consistent with the one specified when adding the APISIX Secrets resource
- secret_name: the secret name in the secrets management service
- key: get the value of a property when the value of the secret is a JSON string

### Required Parameters

| Name                    | Required | Default                                                                                                                                                                                              | Description                                                                                                                                                        |
|-------------------------|----------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| auth_config             | True     |                                                                                                                                                                                                      | Either `auth_config` or `auth_file` must be provided.                                                                                                              |
| auth_config.client_email | True     |                                                                                                                                                                                                    | Email address of the Google Cloud service account.                                                                                                                   |
| auth_config.private_key | True     |                                                                                                                                                                                                      | Private key of the Google Cloud service account.                                                                                                                   |
| auth_config.project_id  | True     |                                                                                                                                                                                                      | Project ID in the Google Cloud service account.                                                                                                                    |
| auth_config.token_uri   | False    | https://oauth2.googleapis.com/token                                                                                                                                                                    | Token URI of the Google Cloud service account.                                                                                                                     |
| auth_config.entries_uri | False    | https://secretmanager.googleapis.com/v1                                                                                                                                                      | 	The API access endpoint for the Google Secrets Manager.                                                                                                                                |
| auth_config.scope      | False    | https://www.googleapis.com/auth/cloud-platform | Access scopes of the Google Cloud service account. See [OAuth 2.0 Scopes for Google APIs](https://developers.google.com/identity/protocols/oauth2/scopes) |
| auth_file               | True     |                                                                                                                                                                                                      | Path to the Google Cloud service account authentication JSON file. Either `auth_config` or `auth_file` must be provided.                                           |
| ssl_verify              | False    | true                                                                                                                                                                                                 | When set to `true`, enables SSL verification as mentioned in [OpenResty docs](https://github.com/openresty/lua-nginx-module#tcpsocksslhandshake).                  |

You need to configure the corresponding authentication parameters, or specify the authentication file through auth_file, where the content of auth_file is in JSON format.

### Example

Here is a correct configuration example:

```
curl http://127.0.0.1:9180/apisix/admin/secrets/gcp/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "auth_config" : {
        "client_email": "email@apisix.iam.gserviceaccount.com",
        "private_key": "private_key",
        "project_id": "apisix-project",
        "token_uri": "https://oauth2.googleapis.com/token",
        "entries_uri": "https://secretmanager.googleapis.com/v1",
        "scope": ["https://www.googleapis.com/auth/cloud-platform"]
    }
}'

```
