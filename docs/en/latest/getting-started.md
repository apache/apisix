---
title: Getting Started
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

## Summary

This guide walks through how you can get up and running with Apache APISIX.

The guide is divided into these three steps:

1. Installing Apache APISIX
2. Creating a Route and binding it with an Upstream
3. Verifying the results after binding with `curl`

This document also introduces some of the advanced features and operations in Apache APISIX like authentication, prefixing a Route, using the APISIX Dashboard, and troubleshooting.

The following `echo` endpoint is used as an example here. This endpoint will return the parameters we pass.

**Request**

The components of the request URL are shown and explained below:

![RequestURL](../../assets/images/requesturl.jpg)

- Protocol: The network transport protocol. `HTTP` protocol is used for this example.
- Port: The port. `80` is used for this example.
- Host: The host. `httpbin.org` is used for this example.
- Path: The path. `/get` is used for this example.
- Query Parameters: The query string. Two strings `foo1` and `foo2` are used for this example.

We can use the `curl` command to send the request:

```bash
curl --location --request GET "http://httpbin.org/get?foo1=bar1&foo2=bar2"
```

**Response**

We receive a JSON response when we send the request:

```json
{
  "args": {
    "foo1": "bar1",
    "foo2": "bar2"
  },
  "headers": {
    "Accept": "*/*",
    "Host": "httpbin.org",
    "User-Agent": "curl/7.29.0",
    "X-Amzn-Trace-Id": "Root=1-6088fe84-24f39487166cce1f0e41efc9"
  },
  "origin": "58.152.81.42",
  "url": "http://httpbin.org/get?foo1=bar1&foo2=bar2"
}
```

## Pre-Requisites

Before you jump ahead, make sure that you have your machine setup with these tools.

- [Docker](https://www.docker.com/) and [Docker Compose](https://docs.docker.com/compose/).

- [curl](https://curl.se/docs/manpage.html) for testing the API. Alternatively, you can use tools like [Hoppscotch](https://hoppscotch.io/) or [Postman](https://www.postman.com/).

<!--
#
#    In addition to the basic Markdown syntax, we use remark-admonitions
#    alongside MDX to add support for admonitions. Admonitions are wrapped
#    by a set of 3 colons.
#    Please refer to https://docusaurus.io/docs/next/markdown-features/admonitions
#    for more detail.
#
-->

:::note Note
If you already have Apache APISIX installed, please skip Step 1, and go to [Step 2](getting-started.md#step-2-create-a-route) directly.
:::

## Step 1: Install Apache APISIX

You can check out [Building Apache APISIX](./how-to-build.md) for different installation methods.

To get started quickly, we will install Apache APISIX with Docker and enable the [Admin API](./admin-api.md).

```bash
# Download the docker-compose file of Apache APISIX
git clone https://github.com/apache/apisix-docker.git
# Switch the current directory to the apisix-docker/example
cd apisix-docker/example
# Start Apache APISIX with docker-compose
docker-compose -p docker-apisix up -d
```

> Apache APISIX already supports ARM64 architecture. To run Apache APISIX on ARM64, run: `docker-compose -p docker-apisix -f docker-compose-arm64.yml up -d` instead of the last step above.

Please remain patient as it will take some time to download the files and spin up the containers.

Once Apache APISIX is running, you can use `curl` to access the Admin API. You can also check if Apache APISIX is running properly by running this command and checking the response.

```bash
# Execute on your host machine (machine running Docker)
curl "http://127.0.0.1:9080/apisix/admin/services/" -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1'
```

This response indicates that Apache APISIX is running successfully.

```json
{
  "count":0,
  "action":"get",
  "node":{
    "key":"/apisix/services",
    "nodes":[],
    "dir":true
  }
}
```

## Step 2: Create a Route

[Routes](./architecture-design/route.md) matches the client's requests based on defined rules, loads and executes the corresponding plugins, and forwards the request to the specified upstream.

From the previous step, we have a running instance of Apache APISIX in Docker. Now let's create a Route.

Apache APISIX provides a powerful [Admin API](./admin-api.md) and [APISIX Dashboard](https://github.com/apache/apisix-dashboard). Here, we will use the Admin API to create a Route and connect it to an [Upstream](./architecture-design/upstream.md) service. When a request arrives, Apache APISIX will forward the request to the specified Upstream service.

We will create a sample configuration for our Route object so that Apache APISIX can forward the request to the corresponding Upstream service.

```bash
curl "http://127.0.0.1:9080/apisix/admin/routes/1" -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" -X PUT -d '
{
  "methods": ["GET"],
  "host": "example.com",
  "uri": "/anything/*",
  "upstream": {
    "type": "roundrobin",
    "nodes": {
      "httpbin.org:80": 1
    }
  }
}'
```

This configuration means that it will forward all matching inbound requests to the upstream service (`httpbin.org:80`) if they meet these specified criterion.

- The HTTP method of the request is `GET`.
- The request header contains the `host` field, and its value is `example.com`.
- The request path matches `/anything/*`. `*` means any sub path. For example `/anything/foo?arg=10`.

Now that the Route has been created, we can access the Upstream service from the address exposed by Apache APISIX.

```bash
curl -i -X GET "http://127.0.0.1:9080/anything/foo?arg=10" -H "Host: example.com"
```

This request will be forwarded to `http://httpbin.org:80/anything/foo?arg=10` by Apache APISIX.

### Create an Upstream

In the previous session we discussed setting up a Route and an Upstream for the Route.

To create an Upstream, we can execute the following command.

```bash
curl "http://127.0.0.1:9080/apisix/admin/upstreams/1" -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" -X PUT -d '
{
  "type": "roundrobin",
  "nodes": {
    "httpbin.org:80": 1
  }
}'
```

We use `roundrobin` as the load balancing mechanism and set `httpbin.org:80` as our Upstream service with an ID of `1`. See [Admin API](./admin-api.md) for more information about the fields.

<!--
#
#    In addition to the basic Markdown syntax, we use remark-admonitions
#    alongside MDX to add support for admonitions. Admonitions are wrapped
#    by a set of 3 colons.
#    Please refer to https://docusaurus.io/docs/next/markdown-features/admonitions
#    for more detail.
#
-->

:::note Note
Creating an Upstream service is not mandatory as we can use a [Plugin](./architecture-design/plugin.md) to intercept the request and then respond directly. However, for the purposes of this guide, we assume that at least one Upstream service needs to be set up.
:::

### Binding the Route to the Upstream

We can now bind a Route to the Upstream service we just created.

```bash
curl "http://127.0.0.1:9080/apisix/admin/routes/1" -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" -X PUT -d '
{
  "uri": "/get",
  "host": "httpbin.org",
  "upstream_id": "1"
}'
```

## Step 3: Validating the Route

We will now access Apache APISIX to test the Route and the bounded Upstream service.

```bash
curl -i -X GET "http://127.0.0.1:9080/get?foo1=bar1&foo2=bar2" -H "Host: httpbin.org"
```

This will return the data from the Upstream service we configured in our route (`httpbin.org`).

## Advanced Features and Operations

This section looks at some of the advanced features and operations available in Apache APISIX like [authentication](#authentication), [prefixing a Route](#prefixing-a-route), using the [APISIX Dashboard](#apisix-dashboard), and [troubleshooting](#troubleshooting).

### Authentication

The Route we created in [step 2](#step-2-create-a-route) is public. This means that anyone knowing the address exposed by Apache APISIX can access the Upstream service.

This is unsafe and amounts to security risks. So, in practical applications, we generally add authentication to the Route to enhance security.

Let's assume for our scenario that we only want a specific user `John` to have access to the Upstream service.

We will use [Consumer](./architecture-design/consumer.md) a [Plugin](./architecture-design/plugin.md) to implement authentication to handle this scenario.

First, we will use the [key-auth](./plugins/key-auth.md) plugin to create a [Consumer](./architecture-design/consumer.md) `John`. We also need to provide the specified key for `John`.

```bash
curl "http://127.0.0.1:9080/apisix/admin/consumers" -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" -X PUT -d '
{
  "username": "john",
  "plugins": {
    "key-auth": {
      "key": "key-of-john"
    }
  }
}'
```

We can now bind `consumer(John)` to the Route. For this, we just need to enable the [key-auth](./plugins/key-auth.md) plugin as shown below.

```bash
curl "http://127.0.0.1:9080/apisix/admin/routes/1" -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" -X PUT -d '
{
  "uri": "/get",
  "host": "httpbin.org",
  "plugins": {
    "key-auth": {}
  },
  "upstream_id": "1"
}'
```

Now with the authentication added, when we try to access the Route we created in [step 2](#step-2-create-a-route) it will trigger an "Unauthorized Error".

To access the Route, we need to add a `Header` named `apikey` with John's key.

```bash
curl -i -X GET http://127.0.0.1:9080/get -H "Host: httpbin.org" -H "apikey: key-of-john"
```

### Prefixing a Route

When you want to add a prefix to your Route but don't want to use the `Host` header, you can use the `proxy-rewrite` Plugin.

```bash
curl "http://127.0.0.1:9080/apisix/admin/routes/1" -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" -X PUT -d '
{
  "uri": "/samplePrefix/get",
  "plugins": {
    "proxy-rewrite": {
      "regex_uri": ["^/samplePrefix/get(.*)", "/get$1"]
    },
    "key-auth": {}
  },
  "upstream_id": "1"
}'
```

Then to invoke the Route you can run:

```bash
curl -i -X GET "http://127.0.0.1:9080/samplePrefix/get?param1=foo&param2=bar" -H "apikey: key-of-john"
```

### APISIX Dashboard

Apache APISIX comes with an intuitive [Dashboard](https://github.com/apache/apisix-dashboard) to make it easy to configure and perform operations.

![Dashboard](../../assets/images/dashboard.jpeg)

<!--
#
#    In addition to the basic Markdown syntax, we use remark-admonitions
#    alongside MDX to add support for admonitions. Admonitions are wrapped
#    by a set of 3 colons.
#    Please refer to https://docusaurus.io/docs/next/markdown-features/admonitions
#    for more detail.
#
-->

### Troubleshooting

You can try these troubleshooting steps if you are unable to proceed as suggested in the docs above.

Please [open an issue](/docs/general/contributor-guide#submit-an-issue) if you run into any bugs or if there are any missing troubleshooting steps.

- Make sure that all required ports (**default 9080/9443/2379**) are available (not used by other systems or processes).

    You can run the command below to terminate the processes that are listening on a specific port (on Unix-based systems).

    ```bash
    sudo fuser -k 9443/tcp
    ```

- If the Docker container keeps restarting or IS failing, log in to the container and observe the logs to diagnose the problem.

    ```bash
    docker logs -f --tail container_id
    ```
