---
title: KMS
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

KMS allows users to store Secrets through some secrets management services (vault, etc.) in APISIX, and read them according to the key when using them, so as to ensure that **Secrets do not exist in plain text throughout the platform**.

APISIX currently supports storing keys in environment variables.

You use KMS functions by specifying format variables in the consumer configuration of the following plugins:

- key-auth

::: note

If a configuration item is: `key: "$ENV://ABC"`, when the actual value corresponding to $ENV://ABC is not retrieved in KMS, the value of the key will be "$ENV://ABC" instead of `nil`.

:::

## Use environment variables to manage keys

Using environment variables to manage keys means that you can save key information in environment variables, and refer to environment variables through variables in a specific format when configuring plugins. APISIX supports referencing system environment variables and environment variables configured through the Nginx `env` directive.

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

Step 2: Reference the environment variable in the key-auth plugin

```bash
curl http://127.0.0.1:9180/apisix/admin/consumers \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
