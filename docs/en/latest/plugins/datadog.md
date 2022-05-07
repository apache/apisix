---
title: datadog
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

`datadog` is a monitoring plugin built into Apache APISIX for seamless integration with [Datadog](https://www.datadoghq.com/), one of the most used monitoring and observability platform for cloud applications. If enabled, this plugin supports multiple powerful types of metrics capture for every request and response cycle that essentially reflects the behaviour and health of the system.

This plugin pushes its custom metrics to the DogStatsD server, comes bundled with Datadog agent (to learn more about how to install a datadog agent, please visit [here](https://docs.datadoghq.com/agent/) ), over the UDP protocol. DogStatsD basically is an implementation of StatsD protocol which collects the custom metrics for Apache APISIX agent, aggregates it into a single data point and sends it to the configured Datadog server.
To learn more about DogStatsD, please visit [DogStatsD](https://docs.datadoghq.com/developers/dogstatsd/?tab=hostagent) documentation.

This plugin provides the ability to push metrics as a batch to the external Datadog agent, reusing the same datagram socket. In case if you did not receive the log data, don't worry give it some time. It will automatically send the logs after the timer function expires in our Batch Processor.

For more info on Batch-Processor in Apache APISIX please refer.
[Batch-Processor](../batch-processor.md)

## Attributes

| Name             | Type   | Requirement  | Default      | Valid       | Description                                                                                |
| -----------      | ------ | -----------  | -------      | -----       | ------------------------------------------------------------                               |
| prefer_name      | boolean | optional    | true         | true/false  | If set to `false`, would use route/service id instead of name(default) with metric tags.   |

The plugin supports the use of batch processors to aggregate and process entries(logs/data) in a batch. This avoids frequent data submissions by the plugin, which by default the batch processor submits data every `5` seconds or when the data in the queue reaches `1000`. For information or custom batch processor parameter settings, see [Batch-Processor](../batch-processor.md#configuration) configuration section.

## Metadata

| Name        | Type    | Requirement |     Default        | Valid         | Description                                                            |
| ----------- | ------  | ----------- |      -------       | -----         | ---------------------------------------------------------------------- |
| host        | string  | optional    |  "127.0.0.1"       |               | The DogStatsD server host address                                      |
| port        | integer | optional    |    8125            |               | The DogStatsD server host port                                         |
| namespace   | string  | optional    |    "apisix"        |               | Prefix for all the custom metrics sent by APISIX agent. Useful for finding entities for metric graph. e.g. (apisix.request.counter)                                        |
| constant_tags | array | optional    | [ "source:apisix" ] |              | Static tags embedded into generated metrics. Useful for grouping metric over certain signals. |

To know more about how to effectively write tags, please visit [here](https://docs.datadoghq.com/getting_started/tagging/#defining-tags)

## Exported Metrics

Apache APISIX agent, for every request response cycle, export the following metrics to DogStatsD server if the datadog plugin is enabled:

| Metric Name               | StatsD Type   | Description               |
| -----------               | -----------   | -------                   |
| Request Counter           | Counter       | No of requests received.   |
| Request Latency           | Histogram     | Time taken to process the request (in milliseconds). |
| Upstream latency          | Histogram     | Time taken to proxy the request to the upstream server till a response is received (in milliseconds). |
| APISIX Latency            | Histogram     | Time taken by APISIX agent to process the request (in milliseconds). |
| Ingress Size              | Timer         | Request body size in bytes. |
| Egress Size               | Timer         | Response body size in bytes. |

The metrics will be sent to the DogStatsD agent with the following tags:

> If there is no suitable value for any particular tag, the tag will simply be omitted.

- **route_name**: Name specified in the route schema definition. If not present or plugin attribute `prefer_name` is set to `false`, it will fall back to the route id value.
- **service_name**: If a route has been created with the abstraction of service, the particular service name/id (based on plugin `prefer_name` attribute) will be used.
- **consumer**: If the route has a linked consumer, the consumer Username will be added as a tag.
- **balancer_ip**: IP of the Upstream balancer that has processed the current request.
- **response_status**: HTTP response status code.
- **scheme**: Scheme that has been used to make the request, such as HTTP, gRPC, gRPCs etc.

## How To Enable

The following is an example on how to enable the datadog plugin for a specific route. We are assuming your datadog agent is already up an running.

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

Now any requests to uri `/hello` will generate aforesaid metrics and push it to DogStatsD server of the datadog agent.

## Disable Plugin

Remove the corresponding json configuration in the plugin configuration to disable the `datadog`.
APISIX plugins are hot-reloaded, therefore no need to restart APISIX.

```shell
$ curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

## Custom Configuration

In the default configuration, the plugin expects the dogstatsd service to be available at `127.0.0.1:8125`. If you wish to update the config, please update the plugin metadata. To know more about the fields of the datadog metadata, see [here](#metadata).

Make a request to _/apisix/admin/plugin_metadata_ endpoint with the updated metadata as following:

```shell
$ curl http://127.0.0.1:9080/apisix/admin/plugin_metadata/datadog -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

This HTTP PUT request will update the metadata and subsequent metrics will be pushed to the `172.168.45.29:8126` endpoint via UDP StatsD. Everything will be hot-loaded, there is no need to restart Apache APISIX instances.

In case, if you wish to revert the datadog metadata schema to the default values, just make another PUT request to the same endpoint with an empty body. For example:

```shell
$ curl http://127.0.0.1:9080/apisix/admin/plugin_metadata/datadog -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '{}'
```
