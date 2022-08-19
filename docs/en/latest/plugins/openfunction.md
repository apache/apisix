---
title: openfunction
keywords:
  - APISIX
  - Plugin
  - OpenFunction
  - openfunction
description: This document contains information about the CNCF OpenFunction Plugin.
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

This Plugin can be configured on a Route and requests will be send to the configured OpenFunction API endpoint as the upstream.

## Attributes

| Name                        | Type    | Required | Default | Valid values | Description                                                                                                |
| --------------------------- | ------- | -------- | ------- | ------------ | ---------------------------------------------------------------------------------------------------------- |
| function_uri                | string  | True     |         |              | function uri. For example, `https://localhost:30858/default/function-sample`.                              |
| ssl_verify                  | boolean | False    | true    |              | When set to `true` verifies the SSL certificate.                                                           |
| authorization               | object  | False    |         |              | Authorization credentials to access functions of OpenFunction.                                      |
| authorization.service_token | string  | False    |         |              | The token format is 'xx:xx' which support basic auth for function entry points.                                      |
| timeout                     | integer | False    | 3000ms  | [100, ...]ms | OpenFunction action and HTTP call timeout in ms.                                                              |
| keepalive                   | boolean | False    | true    |              | When set to `true` keeps the connection alive for reuse.                                                   |
| keepalive_timeout           | integer | False    | 60000ms | [1000,...]ms | Time is ms for connection to remain idle without closing.                                                  |
| keepalive_pool              | integer | False    | 5       | [1,...]      | Maximum number of requests that can be sent on this connection before closing it.                          |

:::note

The `timeout` attribute sets the time taken by the OpenFunction to execute, and the timeout for the HTTP client in APISIX. OpenFunction calls may take time to pull the runtime image and start the container. So, if the value is set too small, it may cause a large number of requests to fail.

:::

## Prerequisites

Before configuring the plugin, you need to have OpenFunction running.
Installation of OpenFunction requires a certain version Kubernetes cluster.
For details, please refer to [Installation](https://openfunction.dev/docs/getting-started/installation/).

### Install OpenFunction via Helm Chart

The example below shows OpenFunction installed in Helm:

```shell
# add the OpenFunction chart repository
helm repo add openfunction https://openfunction.github.io/charts/
helm repo update

#install the OpenFunction chart
kubectl create namespace openfunction
helm install openfunction openfunction/openfunction -n openfunction
```

You can then verify if OpenFunction is ready:

```shell
kubectl get pods --namespace openfunction
```

### Create and Push a Function

You can then create a function follow the [sample](https://github.com/OpenFunction/samples)

When building a function, you’ll need to push your function container image to a container registry like Docker Hub or Quay.io. To do that you’ll need to generate a secret for your container registry first.

```shell
REGISTRY_SERVER=https://index.docker.io/v1/ REGISTRY_USER=<your_registry_user> REGISTRY_PASSWORD=<your_registry_password>
kubectl create secret docker-registry push-secret \
    --docker-server=$REGISTRY_SERVER \
    --docker-username=$REGISTRY_USER \
    --docker-password=$REGISTRY_PASSWORD
```

## Enable the Plugin

You can now configure the Plugin on a specific Route and point to this running OpenFunction service:

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

### Configuring path forwarding

The `OpenFunction` Plugins also supports URL path forwarding while proxying requests to the OpenFunction API endpoints upstream. Extensions to the base request path gets appended to the `function_uri` specified in the Plugin configuration.

:::info IMPORTANT

The `uri` configured on a Route must end with `*` for this feature to work properly. APISIX Routes are matched strictly and the `*` implies that any subpath to this URI would be matched to the same Route.

:::

The example below configures this feature:

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

Now, any requests to the path `hello/123` will invoke the OpenFunction ,and the added path is forwarded:

```shell
curl  http://127.0.0.1:9080/hello/123
```

```shell
Hello, 123!
```

## Disable Plugin

To disable the `openfunction` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
