---
title: skywalking
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - SkyWalking
description: The skywalking Plugin supports the integrating with Apache SkyWalking for request tracing.
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
  <link rel="canonical" href="https://docs.api7.ai/hub/skywalking" />
</head>

## Description

The `skywalking` Plugin supports the integrating with [Apache SkyWalking](https://skywalking.apache.org) for request tracing.

SkyWalking uses its native Nginx Lua tracer to provide tracing, topology analysis, and metrics from both service and URI perspectives. APISIX supports HTTP protocol to interact with the SkyWalking server.

The server currently supports two protocols: HTTP and gRPC. In APISIX, only HTTP is currently supported.

## Static Configurations

By default, service names and endpoint address for the Plugin are pre-configured in the [default configuration](https://github.com/apache/apisix/blob/master/apisix/cli/config.lua).

To customize these values, add the corresponding configurations to `config.yaml`. For example:

```yaml
plugin_attr:
  skywalking:
    report_interval: 3      # Reporting interval time in seconds.
    service_name: APISIX    # Service name for SkyWalking reporter.
    service_instance_name: "APISIX Instance Name"   # Service instance name for SkyWalking reporter.
                                                    # Set to $hostname to get the local hostname.
    endpoint_addr: http://127.0.0.1:12800           # SkyWalking HTTP endpoint.
```

Reload APISIX for changes to take effect.

## Attributes

| Name         | Type   | Required | Default | Valid values | Description                                                                |
|--------------|--------|----------|---------|--------------|----------------------------------------------------------------------------|
| sample_ratio | number | True     | 1       | [0.00001, 1] | Frequency of request sampling. Setting the sample ratio to `1` means to sample all requests. |

## Example

To follow along the example, start a storage, OAP and Booster UI with Docker Compose, following [Skywalking's documentation](https://skywalking.apache.org/docs/main/next/en/setup/backend/backend-docker/). Once set up, the OAP server should be listening on `12800` and you should be able to access the UI at [http://localhost:8080](http://localhost:8080).

Update APISIX configuration file to enable the `skywalking` plugin, which is disabled by default, and update the endpoint address:

```yaml title="config.yaml"
plugins:
  - skywalking
  - ...

plugin_attr:
  skywalking:
    report_interval: 3
    service_name: APISIX
    service_instance_name: APISIX Instance
    endpoint_addr: http://192.168.2.103:12800
```

Reload APISIX for configuration changes to take effect.

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Trace All Requests

The following example demonstrates how you can trace all requests passing through a Route.

Create a Route with `skywalking` and configure the sampling ratio to be 1 to trace all requests:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "skywalking-route",
    "uri": "/anything",
    "plugins": {
      "skywalking": {
        "sample_ratio": 1
      }
    },
    "upstream": {
      "nodes": {
        "httpbin.org:80": 1
      },
      "type": "roundrobin"
    }
  }'
```

Send a few requests to the Route:

```shell
curl -i "http://127.0.0.1:9080/anything"
```

You should receive `HTTP/1.1 200 OK` responses.

In [Skywalking UI](http://localhost:8080), navigate to __General Service__ > __Services__. You should see a service called `APISIX` with traces corresponding to your requests:

![SkyWalking APISIX traces](https://static.apiseven.com/uploads/2025/01/15/UdwiO8NJ_skywalking-traces.png)

### Associate Traces with Logs

The following example demonstrates how you can configure the `skywalking-logger` Plugin on a Route to log information of requests hitting the Route.

Create a Route with the `skywalking-logger` Plugin and configure the Plugin with your OAP server URI:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "skywalking-logger-route",
    "uri": "/anything",
    "plugins": {
      "skywalking": {
        "sample_ratio": 1
      },
      "skywalking-logger": {
        "endpoint_addr": "http://192.168.2.103:12800"
      }
    },
    "upstream": {
      "nodes": {
        "httpbin.org:80": 1
      },
      "type": "roundrobin"
    }
  }'
```

Generate a few requests to the Route:

```shell
curl -i "http://127.0.0.1:9080/anything"
```

You should receive `HTTP/1.1 200 OK` responses.

In [Skywalking UI](http://localhost:8080), navigate to __General Service__ > __Services__. You should see a service called `APISIX` with a trace corresponding to your request, where you can view the associated logs:

![trace context](https://static.apiseven.com/uploads/2025/01/16/soUpXm6b_trace-view-logs.png)

![associated log](https://static.apiseven.com/uploads/2025/01/16/XD934LvU_associated-logs.png)
