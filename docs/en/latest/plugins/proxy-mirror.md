---
title: proxy-mirror
keywords:
  - Apache APISIX
  - API Gateway
  - Proxy Mirror
description: The proxy-mirror Plugin duplicates ingress traffic to APISIX and forwards them to a designated Upstream without interrupting the regular services.
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
  <link rel="canonical" href="https://docs.api7.ai/hub/proxy-mirror" />
</head>

## Description

The `proxy-mirror` Plugin duplicates ingress traffic to APISIX and forwards them to a designated upstream, without interrupting the regular services. You can configure the Plugin to mirror all traffic or only a portion. The mechanism benefits a few use cases, including troubleshooting, security inspection, analytics, and more.

Note that APISIX ignores any response from the Upstream host receiving mirrored traffic.

## Attributes

| Name         | Type   | Required | Default | Valid values | Description                                                                                                               |
|--------------|--------|----------|---------|--------------|---------------------------------------------------------------------------------------------------------------------------|
| host         | string | True     |         |              | Address of the host to forward the mirrored traffic to. The address should contain the scheme but without the path, such as `http://127.0.0.1:8081`.  |
| path         | string | False    |         |              | Path of the host to forward the mirrored traffic to. If unspecified, default to the current URI path of the Route. Not applicable if the Plugin is mirroring gRPC traffic.    |
| path_concat_mode | string | False   |   replace     | ["replace", "prefix"]       | Concatenation mode when `path` is specified. When set to `replace`, the configured `path` would be directly used as the path of the host to forward the mirrored traffic to. When set to `prefix`, the path to forward to would be the configured `path`, appended by the requested URI path of the Route. Not applicable if the Plugin is mirroring gRPC traffic.  |
| sample_ratio | number | False    | 1       | [0.00001, 1] |  Ratio of the requests that will be mirrored. By default, all traffic are mirrored.                         |

## Static Configurations

By default, timeout values for the Plugin are pre-configured in the [default configuration](https://github.com/apache/apisix/blob/master/apisix/cli/config.lua).

To customize these values, add the corresponding configurations to `config.yaml`. For example:

```yaml
plugin_attr:
  proxy-mirror:
    timeout:
      connect: 60s
      read: 60s
      send: 60s
```

Reload APISIX for changes to take effect.

## Examples

The examples below demonstrate how to configure `proxy-mirror` for different scenarios.

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Mirror Partial Traffic

The following example demonstrates how you can configure `proxy-mirror` to mirror 50% of the traffic to a Route and forward them to another Upstream service.

Start a sample NGINX server for receiving mirrored traffic:

```shell
docker run -p 8081:80 --name nginx nginx
```

You should see NGINX access log and error log on the terminal session.

Open a new terminal session and create a Route with `proxy-mirror` to mirror 50% of the traffic:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "traffic-mirror-route",
    "uri": "/get",
    "plugins": {
      "proxy-mirror": {
        "host": "http://127.0.0.1:8081",
        "sample_ratio": 0.5
      }
    },
    "upstream": {
      "nodes": {
        "httpbin.org": 1
      },
      "type": "roundrobin"
    }
  }'
```

Send Generate a few requests to the Route:

```shell
curl -i "http://127.0.0.1:9080/get"
```

You should receive `HTTP/1.1 200 OK` responses for all requests.

Navigating back to the NGINX terminal session, you should see a number of access log entries, roughly half the number of requests generated:

```text
172.17.0.1 - - [29/Jan/2024:23:11:01 +0000] "GET /get HTTP/1.1" 404 153 "-" "curl/7.64.1" "-"
```

This suggests APISIX has mirrored the request to the NGINX server. Here, the HTTP response status is `404` since the sample NGINX server does not implement the Route.

### Configure Mirroring Timeouts

The following example demonstrates how you can update the default connect, read, and send timeouts for the Plugin. This could be useful when mirroring traffic to a very slow backend service.

As the request mirroring was implemented as sub-requests, excessive delays in the sub-requests could lead to the blocking of the original requests. By default, the connect, read, and send timeouts are set to 60 seconds. To update these values, you can configure them in the `plugin_attr` section of the configuration file as such:

```yaml title="conf/config.yaml"
plugin_attr:
  proxy-mirror:
    timeout:
      connect: 2000ms
      read: 2000ms
      send: 2000ms
```

Reload APISIX for changes to take effect.
