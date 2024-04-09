---
title: openfunction
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - OpenFunction
description: This document contains information about the Apache APISIX openfunction Plugin.
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

The `openfunction` Plugin is used to integrate APISIX with [CNCF OpenFunction](https://openfunction.dev/) serverless platform.

This Plugin can be configured on a Route and requests will be sent to the configured OpenFunction API endpoint as the upstream.

## Attributes

| Name                        | Type    | Required | Default | Valid values | Description                                                                                                |
| --------------------------- | ------- | -------- | ------- | ------------ | ---------------------------------------------------------------------------------------------------------- |
| function_uri                | string  | True     |         |              | function uri. For example, `https://localhost:30858/default/function-sample`.                              |
| ssl_verify                  | boolean | False    | true    |              | When set to `true` verifies the SSL certificate.                                                           |
| authorization               | object  | False    |         |              | Authorization credentials to access functions of OpenFunction.                                      |
| authorization.service_token | string  | False    |         |              | The token format is 'xx:xx' which supports basic auth for function entry points.                                      |
| timeout                     | integer | False    | 3000 ms | [100, ...] ms| OpenFunction action and HTTP call timeout in ms.                                                              |
| keepalive                   | boolean | False    | true    |              | When set to `true` keeps the connection alive for reuse.                                                   |
| keepalive_timeout           | integer | False    | 60000 ms| [1000,...] ms| Time is ms for connection to remain idle without closing.                                                  |
| keepalive_pool              | integer | False    | 5       | [1,...]      | Maximum number of requests that can be sent on this connection before closing it.                          |

:::note

The `timeout` attribute sets the time taken by the OpenFunction to execute, and the timeout for the HTTP client in APISIX. OpenFunction calls may take time to pull the runtime image and start the container. So, if the value is set too small, it may cause a large number of requests to fail.

:::

## Prerequisites

Before configuring the plugin, you need to have OpenFunction running.
Installation of OpenFunction requires a certain version Kubernetes cluster.
For details, please refer to [Installation](https://openfunction.dev/docs/getting-started/installation/).

### Create and Push a Function

You can then create a function following the [sample](https://github.com/OpenFunction/samples)

You'll need to push your function container image to a container registry like Docker Hub or Quay.io when building a function. To do that, you'll need to generate a secret for your container registry first.

```shell
REGISTRY_SERVER=https://index.docker.io/v1/ REGISTRY_USER= ${your_registry_user} REGISTRY_PASSWORD= ${your_registry_password}
kubectl create secret docker-registry push-secret \
    --docker-server=$REGISTRY_SERVER \
    --docker-username=$REGISTRY_USER \
    --docker-password=$REGISTRY_PASSWORD
```

## Enable the Plugin

You can now configure the Plugin on a specific Route and point to this running OpenFunction service:

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/hello",
    "plugins": {
        "openfunction": {
            "function_uri": "http://localhost:3233/default/function-sample/test",
            "authorization": {
                "service_token": "test:test"
            }
        }
    }
}'
```

## Example usage

Once you have configured the plugin, you can send a request to the Route and it will invoke the configured function:

```shell
curl -i http://127.0.0.1:9080/hello
```

This will give back the response from the function:

```
hello, test!
```

### Configure Path Transforming

The `OpenFunction` Plugin also supports transforming the URL path while proxying requests to the OpenFunction API endpoints. Extensions to the base request path get appended to the `function_uri` specified in the Plugin configuration.

:::info IMPORTANT

The `uri` configured on a Route must end with `*` for this feature to work properly. APISIX Routes are matched strictly and the `*` implies that any subpath to this URI would be matched to the same Route.

:::

The example below configures this feature:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/hello/*",
    "plugins": {
        "openfunction": {
            "function_uri": "http://localhost:3233/default/function-sample",
            "authorization": {
                "service_token": "test:test"
            }
        }
    }
}'
```

Now, any requests to the path `hello/123` will invoke the OpenFunction, and the added path is forwarded:

```shell
curl  http://127.0.0.1:9080/hello/123
```

```shell
Hello, 123!
```

## Delete Plugin

To remove the `openfunction` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/index.html",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```
