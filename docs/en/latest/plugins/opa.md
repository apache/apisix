---
title: opa
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - Open Policy Agent
  - opa
description: This document contains information about the Apache APISIX opa Plugin.
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

The `opa` Plugin can be used to integrate with [Open Policy Agent (OPA)](https://www.openpolicyagent.org). OPA is a policy engine that helps defininig and enforcing authorization policies, which determines whether a user or application has the necessary permissions to perform a particular action or access a particular resource. Using OPA with APISIX decouples authorization logics from APISIX.

## Attributes

| Name              | Type    | Required | Default | Valid values  | Description                                                                                                                                                                                |
|-------------------|---------|----------|---------|---------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| host              | string  | True     |         |               | Host address of the OPA service. For example, `https://localhost:8181`.                                                                                                                    |
| ssl_verify        | boolean | False    | true    |               | When set to `true` verifies the SSL certificates.                                                                                                                                          |
| policy            | string  | True     |         |               | OPA policy path. A combination of `package` and `decision`. While using advanced features like custom response, you can omit `decision`. When specifying a namespace, use the slash format (`examples/echo`) instead of dot notation (`examples.echo`).  |
| timeout           | integer | False    | 3000ms  | [1, 60000]ms  | Timeout for the HTTP call.                                                                                                                                                                 |
| keepalive         | boolean | False    | true    |               | When set to `true`, keeps the connection alive for multiple requests.                                                                                                                      |
| keepalive_timeout | integer | False    | 60000ms | [1000, ...]ms | Idle time after which the connection is closed.                                                                                                                                            |
| keepalive_pool    | integer | False    | 5       | [1, ...]ms    | Connection pool limit.                                                                                                                                                                     |
| with_route        | boolean | False    | false   |               | When set to true, sends information about the current Route.                                                                                                                               |
| with_service      | boolean | False    | false   |               | When set to true, sends information about the current Service.                                                                                                                             |
| with_consumer     | boolean | False    | false   |               | When set to true, sends information about the current Consumer. Note that this may send sensitive information like the API key. Make sure to turn it on only when you are sure it is safe. |

## Data definition

### APISIX to OPA service

The JSON below shows the data sent to the OPA service by APISIX:

```json
{
    "type": "http",
    "request": {
        "scheme": "http",
        "path": "\/get",
        "headers": {
            "user-agent": "curl\/7.68.0",
            "accept": "*\/*",
            "host": "127.0.0.1:9080"
        },
        "query": {},
        "port": 9080,
        "method": "GET",
        "host": "127.0.0.1"
    },
    "var": {
        "timestamp": 1701234567,
        "server_addr": "127.0.0.1",
        "server_port": "9080",
        "remote_port": "port",
        "remote_addr": "ip address"
    },
    "route": {},
    "service": {},
    "consumer": {}
}
```

Each of these keys are explained below:

- `type` indicates the request type (`http` or `stream`).
- `request` is used when the `type` is `http` and contains the basic request information (URL, headers etc).
- `var` contains the basic information about the requested connection (IP, port, request timestamp etc).
- `route`, `service` and `consumer` contains the same data as stored in APISIX and are only sent if the `opa` Plugin is configured on these objects.

### OPA service to APISIX

The JSON below shows the response from the OPA service to APISIX:

```json
{
    "result": {
        "allow": true,
        "reason": "test",
        "headers": {
            "an": "header"
        },
        "status_code": 401
    }
}
```

The keys in the response are explained below:

- `allow` is indispensable and indicates whether the request is allowed to be forwarded through APISIX.
- `reason`, `headers`, and `status_code` are optional and are only returned when you configure a custom response. See the next section use cases for this.

## Example usage

First, you need to launch the Open Policy Agent environment:

```shell
docker run -d --name opa -p 8181:8181 openpolicyagent/opa:0.35.0 run -s
```

### Basic usage

Once you have the OPA service running, you can create a basic policy:

```shell
curl -X PUT '127.0.0.1:8181/v1/policies/example1' \
    -H 'Content-Type: text/plain' \
    -d 'package example1

import input.request

default allow = false

allow {
    # HTTP method must GET
    request.method == "GET"
}'
```

Then, you can configure the `opa` Plugin on a specific Route:

```shell
curl -X PUT 'http://127.0.0.1:9180/apisix/admin/routes/r1' \
    -H 'X-API-KEY: <api-key>' \
    -H 'Content-Type: application/json' \
    -d '{
    "uri": "/*",
    "plugins": {
        "opa": {
            "host": "http://127.0.0.1:8181",
            "policy": "example1"
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

Now, to test it out:

```shell
curl -i -X GET 127.0.0.1:9080/get
```

```shell
HTTP/1.1 200 OK
```

Now if we try to make a request to a different endpoint the request will fail:

```
curl -i -X POST 127.0.0.1:9080/post
```

```shell
HTTP/1.1 403 FORBIDDEN
```

### Using custom response

You can also configure custom responses for more complex scenarios:

```shell
curl -X PUT '127.0.0.1:8181/v1/policies/example2' \
    -H 'Content-Type: text/plain' \
    -d 'package example2

import input.request

default allow = false

allow {
    request.method == "GET"
}

# custom response body (Accepts a string or an object, the object will respond as JSON format)
reason = "test" {
    not allow
}

# custom response header (The data of the object can be written in this way)
headers = {
    "Location": "http://example.com/auth"
} {
    not allow
}

# custom response status code
status_code = 302 {
    not allow
}'
```

Now you can test it out by changing the `opa` Plugin's policy parameter to `example2` and then making a request:

```shell
curl -i -X GET 127.0.0.1:9080/get
```

```
HTTP/1.1 200 OK
```

Now if you make a failing request, you will see the custom response from the OPA service:

```
curl -i -X POST 127.0.0.1:9080/post
```

```
HTTP/1.1 302 FOUND
Location: http://example.com/auth

test
```

### Sending APISIX data

Let's think about another scenario, when your decision needs to use some APISIX data, such as `route`, `consumer`, etc., how should we do it?

If your OPA service needs to make decisions based on APISIX data like Route and Consumer details, you can configure the Plugin to do so.

The example below shows a simple `echo` policy which will return the data sent by APISIX as it is:

```shell
curl -X PUT '127.0.0.1:8181/v1/policies/echo' \
    -H 'Content-Type: text/plain' \
    -d 'package echo

allow = false
reason = input'
```

Now we can configure the Plugin on the Route to send APISIX data:

```shell
curl -X PUT 'http://127.0.0.1:9180/apisix/admin/routes/r1' \
    -H 'X-API-KEY: <api-key>' \
    -H 'Content-Type: application/json' \
    -d '{
    "uri": "/*",
    "plugins": {
        "opa": {
            "host": "http://127.0.0.1:8181",
            "policy": "echo",
            "with_route": true
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

Now if you make a request, you can see the data from the Route through the custom response:

```shell
curl -X GET 127.0.0.1:9080/get
{
    "type": "http",
    "request": {
        xxx
    },
    "var": {
        xxx
    },
    "route": {
        xxx
    }
}
```

## Delete Plugin

To remove the `opa` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
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
