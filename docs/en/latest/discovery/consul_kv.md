---
title: consul_kv
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

For users who used [nginx-upsync-module](https://github.com/weibocom/nginx-upsync-module) and consul key value for service discovery way, as we Weibo Mobile Team, maybe need it.

Thanks to @fatman-x guy, who developed this module, called `consul_kv`, and its worker process data flow is below:
![](https://user-images.githubusercontent.com/548385/107141841-6ced3e00-6966-11eb-8aa4-bc790a4ad113.png)

## Configuration for discovery client

### Configuration for Consul KV

Add following configuration in `conf/config.yaml` :

```yaml
discovery:
  consul_kv:
    servers:
      - "http://127.0.0.1:8500"
      - "http://127.0.0.1:8600"
    prefix: "upstreams"
    skip_keys:                    # if you need to skip special keys
      - "upstreams/unused_api/"
    timeout:
      connect: 1000               # default 2000 ms
      read: 1000                  # default 2000 ms
      wait: 60                    # default 60 sec
    weight: 1                     # default 1
    fetch_interval: 5             # default 3 sec, only take effect for keepalive: false way
    keepalive: true               # default true, use the long pull way to query consul servers
    default_server:               # you can define default server when missing hit
      host: "127.0.0.1"
      port: 20999
      metadata:
        fail_timeout: 1           # default 1 ms
        weight: 1                 # default 1
        max_fails: 1              # default 1
```

And you can config it in short by default value:

```yaml
discovery:
  consul_kv:
    servers:
      - "http://127.0.0.1:8500"
```

The `keepalive` has two optional values:

- `true`, default and recommend value, use the long pull way to query consul servers
- `false`, not recommend, it would use the short pull way to query consul servers, then you can set the `fetch_interval` for fetch interval

### Register Http API Services

Service register Key&Value template:

```
Key:    {Prefix}/{Service_Name}/{IP}:{Port}
Value: {"weight": <Num>, "max_fails": <Num>, "fail_timeout": <Num>}
```

The register consul key use `upstreams` as prefix by default. The http api service name called `webpages` for example, and you can also use `webpages/oneteam/hello` as service name. The api instance of node's ip and port make up new key: `<IP>:<Port>`.

Now, register nodes into consul:

```shell
curl \
    -X PUT \
    -d ' {"weight": 1, "max_fails": 2, "fail_timeout": 1}' \
    http://127.0.0.1:8500/v1/kv/upstreams/webpages/172.19.5.12:8000

curl \
    -X PUT \
    -d ' {"weight": 1, "max_fails": 2, "fail_timeout": 1}' \
    http://127.0.0.1:8500/v1/kv/upstreams/webpages/172.19.5.13:8000
```

In some case, same keys exist in different consul servers.
To avoid confusion, use the full consul key url path as service name in practice.

### Upstream setting

Here is an example of routing a request with a URL of "/*" to a service which named "http://127.0.0.1:8500/v1/kv/upstreams/webpages/" and use consul_kv discovery client in the registry :

```shell
$ curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -i -d '
{
    "uri": "/*",
    "upstream": {
        "service_name": "http://127.0.0.1:8500/v1/kv/upstreams/webpages/",
        "type": "roundrobin",
        "discovery_type": "consul_kv"
    }
}'
```

The format response as below:

```json
{
  "node": {
    "value": {
      "priority": 0,
      "update_time": 1612755230,
      "upstream": {
        "discovery_type": "consul_kv",
        "service_name": "http://127.0.0.1:8500/v1/kv/upstreams/webpages/",
        "hash_on": "vars",
        "type": "roundrobin",
        "pass_host": "pass"
      },
      "id": "1",
      "uri": "/*",
      "create_time": 1612755230,
      "status": 1
    },
    "key": "/apisix/routes/1"
  },
  "action": "set"
}
```

You could find more usage in the `apisix/t/discovery/consul_kv.t` file.

## Debugging API

It also offers control api for debugging:

```shell
GET /v1/discovery/consul_kv/dump
```

For example:

```shell
# curl http://127.0.0.1:9090/v1/discovery/consul_kv/dump | jq
{
  "config": {
    "fetch_interval": 3,
    "timeout": {
      "wait": 60,
      "connect": 6000,
      "read": 6000
    },
    "prefix": "upstreams",
    "weight": 1,
    "servers": [
      "http://172.19.5.30:8500",
      "http://172.19.5.31:8500"
    ],
    "keepalive": true,
    "default_service": {
      "host": "172.19.5.11",
      "port": 8899,
      "metadata": {
        "fail_timeout": 1,
        "weight": 1,
        "max_fails": 1
      }
    },
    "skip_keys": [
      "upstreams/myapi/gateway/apisix/"
    ]
  },
  "services": {
    "http://172.19.5.31:8500/v1/kv/upstreams/webpages/": [
      {
        "host": "127.0.0.1",
        "port": 30513,
        "weight": 1
      },
      {
        "host": "127.0.0.1",
        "port": 30514,
        "weight": 1
      }
    ],
    "http://172.19.5.30:8500/v1/kv/upstreams/1614480/grpc/": [
      {
        "host": "172.19.5.51",
        "port": 50051,
        "weight": 1
      }
    ],
    "http://172.19.5.30:8500/v1/kv/upstreams/webpages/": [
      {
        "host": "127.0.0.1",
        "port": 30511,
        "weight": 1
      },
      {
        "host": "127.0.0.1",
        "port": 30512,
        "weight": 1
      }
    ]
  }
}
```
