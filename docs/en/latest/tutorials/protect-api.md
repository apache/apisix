---
title: Protect API
keywords:
  - API Gateway
  - Apache APISIX
  - Rate Limit
  - Protect API
description: This article describes how to secure your API with the rate limiting plugin for API Gateway Apache APISIX.
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

This article describes secure your API with the rate limiting plugin for API Gateway Apache APISIX.

## Concept introduction

### Plugin

This represents the configuration of the plugins that are executed during the HTTP request/response lifecycle. A [Plugin](../terminology/plugin.md) configuration can be bound directly to a Route, a Service, a Consumer or a Plugin Config.

:::note

If [Route](../terminology/route.md), [Service](../terminology/service.md), [Plugin Config](../terminology/plugin-config.md) or [Consumer](../terminology/consumer.md) are all bound to the same for plugins, only one plugin configuration will take effect. The priority of plugin configurations is described in [plugin execution order](../terminology/plugin.md#plugins-execution-order). At the same time, there are various stages involved in the plugin execution process. See [plugin execution lifecycle](../terminology/plugin.md#plugins-execution-order).

:::

## Preconditions

Before following this tutorial, ensure you have [exposed the service](./expose-api.md).

## Protect your API

We can use rate limits to limit our API services to ensure the stable operation of API services and avoid system crashes caused by some sudden traffic. We can restrict as follows:

1. Limit the request rate;
2. Limit the number of requests per unit time;
3. Delay request;
4. Reject client requests;
5. Limit the rate of response data.

APISIX provides several plugins for limiting current and speed, including [limit-conn](../plugins/limit-conn.md), [limit-count](../plugins/limit-count.md), [limit- req](../plugins/limit-req.md) and other plugins.

- The `limit-conn` Plugin limits the number of concurrent requests to your services.
- The `limit-req` Plugin limits the number of requests to your service using the leaky bucket algorithm.
- The `limit-count` Plugin limits the number of requests to your service by a given count per time.

Next, we will use the `limit-count` plugin as an example to show you how to protect your API with a rate limit plugin:

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

1. Create a Route.

```shell
curl -i http://127.0.0.1:9180/apisix/admin/routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/index.html",
    "plugins": {
        "limit-count": {
            "count": 2,
            "time_window": 60,
            "rejected_code": 503,
            "key_type": "var",
            "key": "remote_addr"
        }
    },
  "upstream_id": "1"
}'
```

In the above configuration, a Route with ID `1` is created using the upstream made in [Expose Service](./expose-api.md), and the `limit-count` plugin is enabled. The plugin only allows the client to access the upstream service `2` times within `60` seconds. If more than two times, the `503` error code will be returned.

2. Test

```shell
curl http://127.0.0.1:9080/index.html
```

After using the above command to access three times in a row, the following error will appear:

```
<html>
<head><title>503 Service Temporarily Unavailable</title></head>
<body>
<center><h1>503 Service Temporarily Unavailable</h1></center>
<hr><center>openresty</center>
</body>
</html>
```

If the above result is returned, the `limit-count` plugin has taken effect and protected your API.

## More Traffic plugins

In addition to providing plugins for limiting current and speed, APISIX also offers many other plugins to meet the needs of actual scenarios:

- [proxy-cache](../plugins/proxy-cache.md): This plugin provides the ability to cache backend response data. It can be used with other plugins. The plugin supports both disk and memory-based caching. Currently, the data to be cached can be specified according to the response code and request mode, and more complex caching strategies can also be configured through the no_cache and cache_bypass attributes.
- [request-validation](../plugins/request-validation.md): This plugin is used to validate requests forwarded to upstream services in advance.
- [proxy-mirror](../plugins/proxy-mirror.md): This plugin provides the ability to mirror client requests. Traffic mirroring is copying the real online traffic to the mirroring service, so that the online traffic or request content can be analyzed in detail without affecting the online service.
- [api-breaker](../plugins/api-breaker.md): This plugin implements an API circuit breaker to help us protect upstream business services.
- [traffic-split](../plugins/traffic-split.md): You can use this plugin to gradually guide the percentage of traffic between upstreams to achieve blue-green release and grayscale release.
- [request-id](../plugins/request-id.md): The plugin adds a `unique` ID to each request proxy through APISIX for tracking API requests.
- [proxy-control](../plugins/proxy-control.md): This plugin can dynamically control the behavior of NGINX proxy.
- [client-control](../plugins/client-control.md): This plugin can dynamically control how NGINX handles client requests by setting an upper limit on the client request body size.

## More Tutorials

You can refer to the [Observe API](./observe-your-api.md) document to monitor APISIX, collect logs, and track.
