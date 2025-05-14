---
title: lago
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - lago
  - monetization
  - github.com/getlago/lago
description: The lago plugin reports usage to a Lago instance, which allows users to integrate Lago with APISIX for API monetization.
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
  <link rel="canonical" href="https://docs.api7.ai/hub/lago" />
</head>

## Description

The `lago` plugin pushes requests and responses to [Lago Self-hosted](https://github.com/getlago/lago) and [Lago Cloud](https://getlago.com) via the Lago REST API. the plugin allows you to use it with a variety of APISIX built-in features, such as the APISIX consumer and the request-id plugin.

This allows for API monetization or let APISIX to be an AI gateway for AI tokens billing scenarios.

:::disclaimer
Lago owns its trademarks and controls its commercial products and open source projects.

The [https://github.com/getlago/lago](https://github.com/getlago/lago) project uses the `AGPL-3.0` license instead of the `Apache-2.0` license that is the same as Apache APISIX. As a user, you will need to evaluate for yourself whether it is applicable to your business to use the project in a compliant way or to obtain another type of license from Lago. Apache APISIX community does not endorse it.

The plugin does not contain any proprietary code or SDKs from Lago, it is contributed by contributors to Apache APISIX and licensed under the `Apache-2.0` license, which is in line with any other part of APISIX and you don't need to worry about its compliance.
:::

When enabled, the plugin will collect information from the request context (e.g. event code, transaction ID, associated subscription ID) as configured and serialize them into [Event JSON objects](https://getlago.com/docs/api-reference/events/event-object) as required by Lago. They will be added to the buffer and sent to Lago in batches of up to 100. This batch size is a [requirement](https://getlago.com/docs/api-reference/events/batch) from Lago. If you want to modify it, see [batch processor](../batch-processor.md) for more details.

## Attributes

| Name | Type | Required | Default | Valid values | Description |
|---|---|---|---|---|---|
| endpoint_addrs | array[string] | True |  | | Lago API address, like `http://127.0.0.1:3000`, it supports both self-hosted and cloud. If multiple endpoints are configured, the log will be pushed to a randomly determined endpoint from the list. |
| endpoint_uri | string | False | /api/v1/events/batch | | Lago API endpoint, it needs to be set to the batch send endpoint. |
| token | string | True |  | | Lago API key, create one for your organization on Lago dashboard. |
| event_transaction_id | string | True |  | | Event's transaction ID, it is used to identify and de-duplicate the event, it supports string templates containing APISIX and NGINX variables, like `req_${request_id}`, which allows you to use values returned by upstream services or request-id plugin integration |
| event_subscription_id | string | True |  | | Event's subscription ID, which is automatically generated or specified by you when you assign the plan to the customer on Lago, used to associate API consumption to a customer subscription, it supports string templates containing APISIX and NGINX variables, like `cus_${consumer_name}`, which allows you to use values returned by upstream services or APISIX consumer |
| event_code | string | True |  | | Lago billable metric's code for associating an event to a specified billable item |
| event_properties | object | False |  | | Event's properties, used to attach information to an event, this allows you to send certain information on a event to Lago, such as sending HTTP status to take a failed request off the bill, or sending the AI token consumption in the response body for accurate billing, its keys are fixed strings and its values can be string templates containing APISIX and NGINX variables, like `${status}` |
| ssl_verify        | boolean       | False    | true | | If true, verify Lago's SSL certificates. |
| timeout           | integer       | False    | 3000 | [1, 60000] | Timeout for the Lago service HTTP call in milliseconds.  |
| keepalive         | boolean       | False    | true |  | If true, keep the connection alive for multiple requests. |
| keepalive_timeout | integer       | False    | 60000 | >=1000 | Keepalive timeout in milliseconds.  |
| keepalive_pool    | integer       | False    | 5       | >=1 | Maximum number of connections in the connection pool.  |

This Plugin supports using batch processors to aggregate and process events in a batch. This avoids the need for frequently submitting the data. The batch processor submits data every `5` seconds or when the data in the queue reaches `1000`. See [Batch Processor](../batch-processor.md#configuration) for more information or setting your custom configuration.

## Examples

The examples below demonstrate how you can configure `lago` Plugin for typical scenario.

To follow along the examples, start a Lago instance. Refer to [https://github.com/getlago/lago](https://github.com/getlago/lago) or use Lago cloud.

Follow these brief steps to configure the Lago:

1. Get the Lago API Key (also known as `token`), from the Developer page of the Lago dashboard.
2. Next, create the Billable metric used by APISIX, assuming its code is `test`. Set the `Aggregation type` to `Count`; and add a filter with a key of `tier` whose value contains `expensive` to allow us to distinguish between API values, which will be demonstrated later.
3. Create a Plan and add the created metric to it. Its code doesn't matter, you can specify as much as you like. In the `Usage-based charges` section, add the billable metric you just created as a `Metered charge` item. Specify the default price as `1$`. Add a filter, use `tier: expensive` to perform the filtering, and specify its price as `10$`.
4. Select an existing or create a new consumer to assign the Plan you just created to it. You need to specify a `Subscription external ID` (or you can have Lago generate it), which will be used as the APISIX consumer username.

Next we need to configure the APISIX for demonstrates.

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Report API call usage

The following example demonstrates how you can configure the `lago` Plugin on a Route to measuring API call usage.

Create a Route 1 with the `lago`, `request-id`, `key-auth` Plugin and configure it:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "lago-route-1",
    "uri": "/get",
    "plugins": {
      "request-id": {
        "include_in_response": true
      },
      "key-auth": {},
      "lago": {
        "endpoint_addrs": ["http://12.0.0.1:3000"],
        "token": "<Get token from Lago dashboard>",
        "event_transaction_id": "${http_x_request_id}",
        "event_subscription_id": "${http_x_consumer_username}",
        "event_code": "test"
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

Create Route 2:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "lago-route-2",
    "uri": "/anything",
    "plugins": {
      "request-id": {
        "include_in_response": true
      },
      "key-auth": {},
      "lago": {
        "endpoint_addrs": ["http://12.0.0.1:3000"],
        "token": "<Get token from Lago dashboard>",
        "event_transaction_id": "${http_x_request_id}",
        "event_subscription_id": "${http_x_consumer_username}",
        "event_code": "test",
        "event_properties": {
          "tier": "expensive"
        }
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

Creating Consumer:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "<Lago subscription external ID>",
    "plugins": {
      "key-auth": {
        "key": "demo"
      }
    }
  }'
```

Send three requests to two separate routes:

```shell
curl "http://127.0.0.1:9080/get"
curl "http://127.0.0.1:9080/get"
curl "http://127.0.0.1:9080/get"
curl "http://127.0.0.1:9080/anything"
curl "http://127.0.0.1:9080/anything"
curl "http://127.0.0.1:9080/anything"
```

You should receive `HTTP/1.1 200 OK` responses for all requests.

Wait a few seconds, go to the `Developer` page in the Lago dashboard, look at `Events` and you will see 6 event entries sent by APISIX.

If the self-hosted instance's event worker is configured correctly (or if you're using Lago Cloud), you can also see the total amount consumed in real time in the consumer's subscription usage, which should be `3 * 1$ + 3 * 10$ = 33$` according to our demo use case.

## FAQ

### What's this for?

When you make an effort to monetize your API, it's hard to find a ready-made, low-cost solution, so you may have to build your own billing stack, which is complicated.

This plugin allows you to use APISIX to handle API proxies and use Lago as a billing stack through direct integration with Lago, and both the APISIX open source project and Lago will be part of your portfolio, which is a huge time saver.

Every API call results in a Lago event, which allows you to bill users for real usage, i.e. pay-as-you-go, and thanks to our built-in transaction ID (request ID) support, you can simply implement API call logging and troubleshooting for your customers.

In addition to typical API monetization scenarios, APISIX can also do AI tokens-based billing when it is acting as an AI gateway, where each Lago event generated by an API request includes exactly how many tokens were consumed, to allow you to charge the user for a fine-grained per-tokens usage.

### Is it flexible?

Of course, the fact that we make transaction ID, subscription ID as a configuration item and allow you to use APISIX and NGINX variables in it means that it's simple to integrate the plugin with any existing or your own authentication and internal services.

- Use custom authentication: as long as the Lago subscription ID represented by the user ID is registered as an APISIX variable, it will be available from there, so custom authentication is completely possible!
- Integration with internal services: sometimes you may not need the APISIX built-in `request-id` plugin, it doesn't matter, you can have your internal service (APISIX upstream) generate it and include it in the HTTP response header so that you can access it by way of an NGINX variable in the transaction ID.

Support for event properties is provided, this allows you to set special values on specific APIs, for example if your service has 100 APIs, and you want to enable general billing on all of them and special configure them on a few specific APIs to apply different pricing, this will work, as we did in the demo above.

### Events are not pushed properly

Look at `error.log` for such a log.

```text
2023/04/30 13:45:46 [error] 19381#19381: *1075673 [lua] batch-processor.lua:95: Batch Processor[lago logger] failed to process entries: lago api returned status: 400, body: <error message>, context: ngx.timer, client: 127.0.0.1, server: 0.0.0.0:9080
```

The error can be diagnosed based on the error code in the `failed to process entries: lago api returned status: 400, body: <error message>` and the response body of the lago server.

### Reliability of reporting

The plugin may encounter a network problem that prevents the node where the gateway is located from communicating with the Lago API, in which case APISIX will discard the batch according to the [batch processor](../batch-processor.md) configuration, the batch will be discarded if the specified number of retries are made and the dosage still cannot be sent.

Discarded events are permanently lost, so it is recommended that you use this plugin in conjunction with other logging mechanisms and perform event replay after Lago is unavailable causing data to be discarded to ensure that all logs are correctly sent to Lago.

### Will the event duplicate?

While APISIX performs retries based on the [batch processor](../batch-processor.md) configuration, you don't need to worry about duplicate events being reported to Lago.

The `event_transcation_id` and `timestamp` are generated and logged after the request is processed on the APISIX side, and Lago de-duplicates the event based on them.
So even if a retry is triggered because the network causes Lago to send a `success` response that is not received by APISIX, the event is still not duplicated on Lago.

### Performance Impacts

The plugin is logically simple and reliable, it just builds a Lago event object for each request, buffers and sends them in bulk. The logic is not coupled to the request proxy path, so this does not cause latency to rise for requests going through the gateway.

Technically, the logic is executed in the NGINX log phase and [batch processor](./batch-processor.md) timer, so this does not affect the request itself.

### Resource overhead

For the reasons mentioned above in performance impact section, the plugin does not result in a significant resource overhead, it only consumes a few worker memory to buffer events for batching.
