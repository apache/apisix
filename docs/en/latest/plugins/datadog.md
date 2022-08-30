---
title: datadog
keywords:
  - APISIX
  - API Gateway
  - Plugin
  - Datadog
description: This document contains information about the Apache APISIX datadog Plugin.
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

The `datadog` monitoring Plugin is for seamless integration of APISIX with [Datadog](https://www.datadoghq.com/), one of the most used monitoring and observability platform for cloud applications.

When enabled, the Plugin supports multiple metric capture types for request and response cycles.

This Plugin, pushes its custom metrics to the [DogStatsD](https://docs.datadoghq.com/developers/dogstatsd/?tab=hostagent) server over UDP protocol and comes bundled with [Datadog agent](https://docs.datadoghq.com/agent/).

DogStatsD implements the StatsD protocol which collects the custom metrics for the Apache APISIX agent, aggregates them into a single data point, and sends it to the configured Datadog server.

This Plugin provides the ability to push metrics as a batch to the external Datadog agent, reusing the same datagram socket. It might take some time to receive the log data. It will be automatically sent after the timer function in the [batch processor](../batch-processor.md) expires.

## Attributes

| Name        | Type    | Required | Default | Valid values | Description                                                                            |
| ----------- | ------- | -------- | ------- | ------------ | -------------------------------------------------------------------------------------- |
| prefer_name | boolean | False    | true    | [true,false] | When set to `false`, uses Route/Service ID instead of name (default) with metric tags. |

This Plugin supports using batch processors to aggregate and process entries (logs/data) in a batch. This avoids the need for frequently submitting the data. The batch processor submits data every `5` seconds or when the data in the queue reaches `1000`. See [Batch Processor](../batch-processor.md#configuration) for more information or setting your custom configuration.

## Metadata

You can configure the Plugin through the Plugin metadata.

| Name          | Type    | Required | Default             | Description                                                                                                                               |
| ------------- | ------- | -------- | ------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| host          | string  | False    | "127.0.0.1"         | DogStatsD server host address.                                                                                                            |
| port          | integer | False    | 8125                | DogStatsD server host port.                                                                                                               |
| namespace     | string  | False    | "apisix"            | Prefix for all custom metrics sent by APISIX agent. Useful for finding entities for metrics graph. For example, `apisix.request.counter`. |
| constant_tags | array   | False    | [ "source:apisix" ] | Static tags to embed into generated metrics. Useful for grouping metrics over certain signals.                                            |

:::tip

See [defining tags](https://docs.datadoghq.com/getting_started/tagging/#defining-tags) to know more about how to effectively use tags.

:::

By default, the Plugin expects the DogStatsD service to be available at `127.0.0.1:8125`. If you want to change this, you can update the Plugin metadata as shown below:

```shell
curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/datadog -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "host": "172.168.45.29",
    "port": 8126,
    "constant_tags": [
        "source:apisix",
        "service:custom"
    ],
    "namespace": "apisix"
}'
```

To reset to default configuration, make a PUT request with empty body:

```shell
curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/datadog -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '{}'
```

## Exported metrics

When the `datadog` Plugin is enabled, the APISIX agent exports the following metrics to the DogStatsD server for each request/response cycle:

| Metric name      | StatsD type | Description                                                                                           |
| ---------------- | ----------- | ----------------------------------------------------------------------------------------------------- |
| Request Counter  | Counter     | Number of requests received.                                                                          |
| Request Latency  | Histogram   | Time taken to process the request (in milliseconds).                                                  |
| Upstream latency | Histogram   | Time taken to proxy the request to the upstream server till a response is received (in milliseconds). |
| APISIX Latency   | Histogram   | Time taken by APISIX agent to process the request (in milliseconds).                                  |
| Ingress Size     | Timer       | Request body size in bytes.                                                                           |
| Egress Size      | Timer       | Response body size in bytes.                                                                          |

The metrics will be sent to the DogStatsD agent with the following tags:

- `route_name`: Name specified in the Route schema definition. If not present or if the attribute `prefer_name` is set to false, falls back to the Route ID.
- `service_name`: If a Route has been created with an abstracted Service, the Service name/ID based on the attribute `prefer_name`.
- `consumer`: If the Route is linked to a Consumer, the username will be added as a tag.
- `balancer_ip`: IP address of the Upstream balancer that processed the current request.
- `response_status`: HTTP response status code.
- `scheme`: Request scheme such as HTTP, gRPC, and gRPCs.

:::note

If there are no suitable values for any particular tag, the tag will be omitted.

:::

## Enabling the Plugin

Once you have your Datadog agent running, you can enable the Plugin as shown below:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
      "plugins": {
            "datadog": {}
       },
      "upstream": {
           "type": "roundrobin",
           "nodes": {
               "127.0.0.1:1980": 1
           }
      },
      "uri": "/hello"
}'
```

Now, requests to the endpoint `/hello` will generate metrics and push it to the DogStatsD server.

## Disable Plugin

To disable the `datadog` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/hello",
    "plugins": {},
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```
