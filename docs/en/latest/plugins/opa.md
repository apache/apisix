---
title: opa
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

The `opa` plugin is used to integrate with [Open Policy Agent](https://www.openpolicyagent.org). By using this plugin, users can decouple functions such as authentication and access to services and reduce the complexity of the application system.

## Attributes

| Name | Type | Requirement | Default | Valid | Description |
| -- | -- | -- | -- | -- | -- |
| host | string | required |   |   | Open Policy Agent service host (eg. https://localhost:8181) |
| ssl_verify | boolean | optional | true |   | Whether to verify the certificate |
| policy | string | required |   |   | OPA policy path (It is a combination of `package` and `decision`. When you need to use advanced features such as custom response, `decision` can be omitted) |
| timeout | integer | optional | 3000ms | [1, 60000]ms | HTTP call timeout. |
| keepalive | boolean | optional | true |   | HTTP keepalive |
| keepalive_timeout | integer | optional | 60000ms | [1000, ...]ms | keepalive idle timeout |
| keepalive_pool | integer | optional | 5 | [1, ...]ms | Connection pool limit |
| with_route | boolean | optional | false |   | Whether to send information about the current route. |
| with_service | boolean | optional | false |   | Whether to send information about the current service. |
| with_consumer | boolean | optional | false |   | Whether to send information about the current consumer. (It may contain sensitive information such as apikey, so please turn it on only if you are sure it is safe) |

## Data Definition

### APISIX to OPA service

The `type` indicates that the request type. (e.g. `http` or `stream`)
The `reqesut` is used when the request type is `http`, it contains the basic information of the request. (e.g. url, header)
The `var` contains basic information about this requested connection. (e.g. IP, port, request timestamp)
The `route`, `service`, and `consumer` will be sent only after the `opa` plugin has enabled the relevant features, and their contents are same as those stored by APISIX in etcd.

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

### OPA service response to APISIX

In the response, `result` is automatically added by OPA. The `allow` is indispensable and will indicate whether the request is allowed to be forwarded through the APISIX.
The `reason`, `headers`, and `status_code` are optional and are only returned when you need to use a custom response, as you'll see in the next section with the actual use case for it.

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

## Example

First, you need to launch the Open Policy Agent environment.

```shell
$ docker run -d --name opa -p 8181:8181 openpolicyagent/opa:0.35.0 run -s
```

### Basic Use Case

You can create a basic policy for testing.

```shell
$ curl -X PUT '127.0.0.1:8181/v1/policies/example1' \
    -H 'Content-Type: text/plain' \
    -d 'package example1

import input.request

default allow = false

allow {
    # HTTP method must GET
    request.method == "GET"
}'
```

After that, you can create a route and turn on the `opa` plugin.

```shell
$ curl -X PUT 'http://127.0.0.1:9080/apisix/admin/routes/r1' \
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

Try it out.

```shell
# Successful request
$ curl -i -X GET 127.0.0.1:9080/get
HTTP/1.1 200 OK

# Failed request
$ curl -i -X POST 127.0.0.1:9080/post
HTTP/1.1 403 FORBIDDEN
```

### Complex Use Case (custom response)

Next, let's think about some more complex scenarios.

When you need to return a custom error message for an incorrect request, you can implement it this way.

```shell
$ curl -X PUT '127.0.0.1:8181/v1/policies/example2' \
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

Update the route and set `opa` plugin's `policy` parameter to `example2`. Then, let's try it.

```shell
# Successful request
$ curl -i -X GET 127.0.0.1:9080/get
HTTP/1.1 200 OK

# Failed request
$ curl -i -X POST 127.0.0.1:9080/post
HTTP/1.1 302 FOUND
Location: http://example.com/auth

test
```

### Complex Use Case (send APISIX data)

Let's think about another scenario, when your decision needs to use some APISIX data, such as `route`, `consumer`, etc., how should we do it?

Create a simple policy `echo`, which will return the data sent by APISIX to the OPA service as is, so we can simply see them.

```shell
$ curl -X PUT '127.0.0.1:8181/v1/policies/echo' \
    -H 'Content-Type: text/plain' \
    -d 'package echo

allow = false
reason = input'
```

Next, update the config of the route to enable sending route data.

```shell
$ curl -X PUT 'http://127.0.0.1:9080/apisix/admin/routes/r1' \
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

Try it. As you can see, we output this data with the help of the custom response body function described above, along with the data from the route.

```shell
$ curl -X GET 127.0.0.1:9080/get
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
