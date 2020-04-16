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

[Chinese](getting-started-cn.md)

# Quick Start Guide

The goal of this guide is to get started with APISIX and to configure a secured public API with APISIX.
By the end of this guide, you will have a working APISIX setup and a new service which will route to a public API, which is secured by an API key.

The following GET endpoint will be used for the purpose of this tutorial. This will act as an echo endpoint and will return the parameters which are sent to the API.

```bash
$ curl --location --request GET "https://httpbin.org/get?foo1=bar1&foo2=bar2"
```

Let's deconstruct the above URL.

- Scheme: HTTPS
- Host/Address: httpbin.org
- Port: 443
- URI: /get
- Query Parameters: foo1, foo2

## Prerequisites

- This guide uses docker and docker-compose to setup APISIX. But if you have already installed APISIX in other ways, you can just skip to [step 2](getting-started.md#step-2-create-a-route-in-apisix).
- Curl: The guide uses curl command for API testing, but you can also use any other tool of your choice (Eg- Postman).

## Step 1: Install APISIX

APISIX is available to install in multiple operating environments. The [following document](how-to-build.md#installation-via-source-release) shows the installation steps in multiple platforms.
For the quick start let's use the docker based set up. To start the APISIX server, clone the following [repository](https://github.com/apache/incubator-apisix-docker) and navigate to the example folder and execute the following commands.

This command will start the APISIX server and the admin API will be available in 9080 port (HTTPS port: 9443).

```bash
$ git clone https://github.com/apache/incubator-apisix-docker.git
$ cd example
$ docker-compose -p docker-apisix up -d
```

It will take a while to download the source for the first time. But the consequent loads will be very fast.
After the docker containers have started visit the following link to check if you are getting a successful response.

```bash
$ curl "http://127.0.0.1:9080/apisix/admin/services/" -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1'
```

The following will be the response from the Admin API.

```json
{
    "node": {
        "createdIndex": 6,
        "modifiedIndex": 6,
        "key": "/apisix/services",
        "dir": true
        },
    "action": "get"
}
```

## Step 2: Create a Route in APISIX

APISIX provides a powerful Admin API and a [dashboard](https://github.com/apache/incubator-apisix-dashboard) for configuring the routes/services/plugins.
The quickstart guide will use the Admin API for configuring the routes.

A micro-service can be configured via APISIX through the relationship between several entities such as routes, services, upstream, and plugins.
The route matches the client request and specifies how they are sent to the upstream (backend API/Service) after they reach APISIX.
Services provide an abstraction to the upstream services. Therefore, you can create a single service and reference it in multiple routes.
Check out the architecture document for more information.

Technically all this information(upstream or service, plugins) can be included inside a route configuration. The route consists of three main parts.

- Matching Rules:

    Let's take the following scenario.
    http://example.com/services/users

    The URL above hosts all the micro services related to the users(getUser/ GetAllUsers) in the system. For example the GetAllUsers endpoint can be reached via the following URL (http://example.com/services/users/GetAllUsers)
    Now you want to expose all the `GET` endpoints(micro-services) under the `users` path. The following will be the route configuration for matching such request.

    ```json
    {
        "methods": ["GET"],
        "host": "example.com",
        "uri": "/services/users/*",
        ... Additional Configurations
    }
    ```

    With the above matching rule you can communicate to APISIX via the following command.

    ```bash
    curl -i -X GET "http://{apisix_server.com}:{port}/services/users/getAllUsers?limit=10" -H "Host: example.com"
    ```

- Upstream information:

    Upstream is a virtual host abstraction that performs load balancing on a given set of service nodes according to configuration rules.
    Thus a single upstream configuration can comprise of multiple servers which offers the same service. Each node will comprise of a key(address/ip : port) and a value(weight of the node).
    The service can be load balanced through a round robin or consistent hashing (cHash) mechanism.

    When configuring a route you can either set the upstream information or use service abstraction to refer the upstream information.

- Plugins

    Plugins allows you to extend the capabilities of APISIX and to implement arbitrary logic which can interface with the HTTP request/response lifecycle.
    Therefore, if you want to authenticate the API then you can include the Key Auth plugin to enforce authentication for each request.

### Create an Upstream

Execute the following command to create an upstream with the id of '50' in APISIX. Let's use the round-robin mechanism for load balancing.

```bash
curl "http://127.0.0.1:9080/apisix/admin/upstreams/50" -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "type": "roundrobin",
    "nodes": {
        "httpbin.org:443": 1
    }
}'
```

### Add a Route to Access the Upstream

By default APISIX proxies the request via the HTTP protocol. As our backend is hosted in a HTTPS environment, let's use the proxy-rewrite plugin to change the scheme to HTTPS.

```bash
curl "http://127.0.0.1:9080/apisix/admin/routes/5" -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/get",
    "host": "httpbin.org",
    "plugins": {
        "proxy-rewrite": {
          "scheme": "https"
        }
    },
    "upstream_id": 50
}'
```

### Call APISIX

Now lets call APISIX to test the newly configured route.

```bash
curl -i -X GET "http://127.0.0.1:9080/get?foo1=bar1&foo2=bar2" -H "Host: httpbin.org"
```

The API is available via the HTTPs(9443) endpoint as well. If you are using a self signed certificate then use the `-k` parameter to ignore the self-signed certificate error by the curl command.

```bash
curl -i -k -X GET "https://127.0.0.1:9443/get?foo1=bar1&foo2=bar2" -H "Host: httpbin.org"
```

## Step 3: Add authentication for the service

Now lets protect the newly created APISIX endpoint/route as it is currently open to the public.
Execute the following command to create a user called John with a dedicated api-key.

Note: APISIX supports multiple authentication mechanism, view the plugin docs to learn more.

```shell
curl http://127.0.0.1:9080/apisix/admin/consumers -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "username": "john",
    "plugins": {
        "key-auth": {
            "key": "superSecretAPIKey"
        }
    }
}'
```

Now, let's configure our endpoint to include the key-auth plugin.

```bash
curl http://127.0.0.1:9080/apisix/admin/routes/5 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/get",
    "host": "httpbin.org",
    "plugins": {
        "proxy-rewrite": {
          "scheme": "https"
        },
        "key-auth": {}
    },
    "upstream_id": 50
}'
```

As the route is secured by the key-auth plugin the former curl command to access the API will produce an unauthorized access error.
Use the command below to securely access the endpoint now.

```bash
curl -i -X GET http://127.0.0.1:9080/get -H "Host: httpbin.org" -H 'apikey: superSecretAPIKey'
```

## Add a prefix to the route

Now lets say you want to add a prefix (eg: samplePrefix) to the route and do not want to use the `host` header then you can use
the proxy rewrite plugin to do it.

```bash
curl http://127.0.0.1:9080/apisix/admin/routes/5 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/samplePrefix/get",
    "plugins": {
        "proxy-rewrite": {
          "scheme": "https",
          "regex_uri": ["^/samplePrefix/get(.*)", "/get$1"]
        },
        "key-auth": {}
    },
    "upstream_id": 50
}'
```

Now you can invoke the route with the following command:

```bash
curl -i -X GET http://127.0.0.1:9080/samplePrefix/get?param1=foo&param2=bar -H 'apikey: superSecretAPIKey'
```

## APISIX Dashboard

As of now the API calls to the APISIX has been orchestrated by using the Admin API. However, APISIX also provides
a web application to perform the similar. The dashboard is available in the following
[repository](https://github.com/apache/incubator-apisix). The dashboard is intuitive and you can orchestrate the
same route configurations via the dashboard as well.

![Dashboard](images/dashboard.png)

### Troubleshooting

- Make sure the required ports are not being used by other systems/processes (The default ports are: 9080, 9443, 2379).
The following is the command to kill a process which is listening to a specific port (in unix based systems).

    ```bash
    sudo fuser -k 9443/tcp
    ```

- If the docker container is continuously restarting/failing, login to the container and observe the logs to diagnose the issue.

    ```bash
    docker logs -f --tail container_id
    ```
