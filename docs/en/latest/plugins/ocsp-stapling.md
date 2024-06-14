---
title: ocsp-stapling
keywords:
  - Apache APISIX
  - Plugin
  - ocsp-stapling
description: This document contains information about the Apache APISIX ocsp-stapling Plugin.
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

The `ocsp-stapling` Plugin dynamically sets the behavior of [OCSP stapling](https://nginx.org/en/docs/http/ngx_http_ssl_module.html#ssl_stapling) in Nginx.

## Enable Plugin

This Plugin is disabled by default. Modify the config file to enable the plugin:

```yaml title="./conf/config.yaml"
plugins:
  - ...
  - ocsp-stapling
```

After modifying the config file, reload APISIX or send an hot-loaded HTTP request through the Admin API to take effect:

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/plugins/reload -H "X-API-KEY: $admin_key" -X PUT
```

## Attributes

The attributes of this plugin are stored in specific field `ocsp_stapling` within SSL Resource.

| Name           | Type                 | Required | Default       | Valid values | Description                                                                                   |
|----------------|----------------------|----------|---------------|--------------|-----------------------------------------------------------------------------------------------|
| enabled        | boolean              | False    | false         |              | Like the `ssl_stapling` directive, enables or disables OCSP stapling feature.                 |
| skip_verify    | boolean              | False    | false         |              | Like the `ssl_stapling_verify` directive, enables or disables verification of OCSP responses. |
| ssl_stapling_responder | string       | False    | ""            |"http://..."  | Like the `ssl_stapling_responder` directive, overrides the URL of the OCSP responder specified in the "Authority Information Access" certificate extension of server certificates. |
| ssl_ocsp    | string                  | False    | "off"         |["off", "leaf"]| Like the `ssl_ocsp` directive, enables or disables OCSP validation of the client certificate. |
| ssl_ocsp_responder        | string    | False    | ""            |"http://..."  | Like the `ssl_ocsp_responder` directive, overrides the URL of the OCSP responder specified in the "Authority Information Access" certificate extension for validation of client certificates.  |
| cache_ttl      | integer              | False    | 3600          | >= 60        | Specifies the expired time of OCSP response cache.                                            |

## Example usage

You should create an SSL Resource first, and the certificate of the server certificate issuer should be known. Normally the fullchain certificate works fine.

Create an SSL Resource as such:

```shell
curl http://127.0.0.1:9180/apisix/admin/ssls/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "cert" : "'"$(cat server.crt)"'",
    "key": "'"$(cat server.key)"'",
    "snis": ["test.com"],
    "ocsp_stapling": {
        "enabled": true
    }
}'
```

Next, establish a secure connection to the server, request the SSL/TLS session status, and display the output from the server:

```shell
echo -n "Q" | openssl s_client -status -connect localhost:9443 -servername test.com 2>&1 | cat
```

```
...
CONNECTED(00000003)
OCSP response:
======================================
OCSP Response Data:
    OCSP Response Status: successful (0x0)
...
```

To disable OCSP stapling feature, you can make a request as shown below:

```shell
curl http://127.0.0.1:9180/apisix/admin/ssls/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "cert" : "'"$(cat server.crt)"'",
    "key": "'"$(cat server.key)"'",
    "snis": ["test.com"],
    "ocsp_stapling": {
        "enabled": false
    }
}'
```

## OCSP validation of the client certificate

This feature can be enabled on a specific Route, and requires that the current SSL resource has enabled mTLS mode.

Create an SSL Resource as such:

```shell
curl http://127.0.0.1:9180/apisix/admin/ssls/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "cert" : "'"$(cat server.crt)"'",
    "key": "'"$(cat server.key)"'",
    "snis": ["test.com"],
    "client": {
        "ca": "'"$(cat ca.crt)"'"
    },
    "ocsp_stapling": {
        "enabled": true，
        "ssl_ocsp": "leaf"
    }
}'
```

Enables this Plugin on the specified Route:

```shell
curl -i http://127.0.0.1:9180/apisix/admin/routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/",
    "plugins": {
        "ocsp-stapling": {}
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "httpbin.org": 1
        }
    }
}'
```

Once you have configured the Route as shown above, you can make a request as shown below:

```shell
curl --resolve "test.com:9443:127.0.0.1" https://test.com:9443/ -k --cert client.crt --key client.key
```

If the current client certificate OCSP validation passes, a normal response will be returned. If the validation fails or an error occurs during the validation process, an HTTP 400 certificate error response will be returned.

Disabling this feature only requires deleting the plugin on the corresponding route, but it should be noted that the OCSP stapling feature of the server certificate is still in effect and controlled by the corresponding SSL resource. You can set `ssl_ocsp` to `"off"` to disable all client certificate OCSP validation behavior for the current SSL resource.

```shell
# Disable client certificate OCSP validation behavior on specified Route
curl -i http://127.0.0.1:9180/apisix/admin/routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "httpbin.org": 1
        }
    }
}'

# Disable all client certificate OCSP validation behavior
curl http://127.0.0.1:9180/apisix/admin/ssls/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "cert" : "'"$(cat server.crt)"'",
    "key": "'"$(cat server.key)"'",
    "snis": ["test.com"],
    "client": {
        "ca": "'"$(cat ca.crt)"'"
    },
    "ocsp_stapling": {
        "enabled": true，
        "ssl_ocsp": "off"
    }
}'
```

## Delete Plugin

Make sure all your SSL Resource doesn't contains `ocsp_stapling` field anymore. To remove this field, you can make a request as shown below:

```shell
curl http://127.0.0.1:9180/apisix/admin/ssls/1 \
-H "X-API-KEY: $admin_key" -X PATCH -d '
{
    "ocsp_stapling": null
}'
```

Modify the config file `./conf/config.yaml` to disable the plugin:

```yaml title="./conf/config.yaml"
plugins:
  - ...
  # - ocsp-stapling
```

After modifying the config file, reload APISIX or send an hot-loaded HTTP request through the Admin API to take effect:

```shell
curl http://127.0.0.1:9180/apisix/admin/plugins/reload -H "X-API-KEY: $admin_key" -X PUT
```
