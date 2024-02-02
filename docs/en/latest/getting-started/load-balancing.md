---
title: Load Balancing
slug: /getting-started/load-balancing
---

<head>
  <link rel="canonical" href="https://docs.api7.ai/apisix/getting-started/load-balancing" />
</head>

> The Getting Started tutorials are contributed by [API7.ai](https://api7.ai/).

Load balancing manages traffic between clients and servers. It is a mechanism used to decide which server handles a specific request, allowing for improved performance, scalability, and reliability. Load balancing is a key consideration in designing systems that need to handle a large volume of traffic.

Apache APISIX supports weighted round-robin load balancing, in which incoming traffic are distributed across a set of servers in a cyclical pattern, with each server taking a turn in a predefined order.

In this tutorial, you will create a route with two upstream services and enable round-robin load balancing to distribute traffic between the two services.

## Prerequisite(s)

1. Complete [Get APISIX](./README.md) to install APISIX.
2. Understand APISIX [Route and Upstream](./configure-routes.md#what-is-a-route).

## Enable Load Balancing

Let's create a route with two upstream services. All requests sent to the `/headers` endpoint will be forwarded to [httpbin.org](https://httpbin.org/headers) and [mock.api7.ai](https://mock.api7.ai/headers), which should echo back the requester's headers.

```shell
curl -i "http://127.0.0.1:9180/apisix/admin/routes" -X PUT -d '
{
  "id": "getting-started-headers",
  "uri": "/headers",
  "upstream" : {
    "type": "roundrobin",
    "nodes": {
      "httpbin.org:443": 1,
      "mock.api7.ai:443": 1
    },
    "pass_host": "node",
    "scheme": "https"
  }
}'
```

You will receive an `HTTP/1.1 201 Created` response if the route was created successfully.

:::info

1. The `pass_host` field is set to `node` to pass the host header to the upstream.
2. The `scheme` field is set to `https` to enable TLS when sending requests to the upstream.

:::

## Validate

The two services respond with different data.

From `httpbin.org`:

```json
{
  "headers": {
    "Accept": "*/*",
    "Host": "httpbin.org",
    "User-Agent": "curl/7.58.0",
    "X-Amzn-Trace-Id": "Root=1-63e34b15-19f666602f22591b525e1e80",
    "X-Forwarded-Host": "localhost"
  }
}
```

From `mock.api7.ai`:

```json
{
  "headers": {
    "accept": "*/*",
    "host": "mock.api7.ai",
    "user-agent": "curl/7.58.0",
    "content-type": "application/json",
    "x-application-owner": "API7.ai"
  }
}
```

Let's generate 100 requests to test the load-balancing effect:

```shell
hc=$(seq 100 | xargs -I {} curl "http://127.0.0.1:9080/headers" -sL | grep "httpbin" | wc -l); echo httpbin.org: $hc, mock.api7.ai: $((100 - $hc))
```

The result shows the requests were distributed over the two services almost equally:

```text
httpbin.org: 51, mock.api7.ai: 49
```

## What's Next

You have learned how to configure load balancing. In the next tutorial, you will learn how to configure key authentication.
