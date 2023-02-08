---
title: consul
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

APACHE APISIX supports Consul as a service discovery

## Configuration for discovery client

### Configuration for Consul

First of all, we need to add following configuration in `conf/config.yaml` :

```yaml
discovery:
  consul:
    servers:                      # make sure service name is unique in these consul servers
      - "http://127.0.0.1:8500"   # `http://127.0.0.1:8500` and `http://127.0.0.1:8600` are different clusters
      - "http://127.0.0.1:8600"   # `consul` service is default skip service
    skip_services:                # if you need to skip special services
      - "service_a"
    timeout:
      connect: 1000               # default 2000 ms
      read: 1000                  # default 2000 ms
      wait: 60                    # default 60 sec
    weight: 1                     # default 1
    fetch_interval: 5             # default 3 sec, only take effect for keepalive: false way
    keepalive: true               # default true, use the long pull way to query consul servers
    default_service:              # you can define default service when missing hit
      host: "127.0.0.1"
      port: 20999
      metadata:
        fail_timeout: 1           # default 1 ms
        weight: 1                 # default 1
        max_fails: 1              # default 1
    dump:                         # if you need, when registered nodes updated can dump into file
       path: "logs/consul.dump"
       expire: 2592000            # unit sec, here is 30 day
```

And you can config it in short by default value:

```yaml
discovery:
  consul:
    servers:
      - "http://127.0.0.1:8500"
```

The `keepalive` has two optional values:

- `true`, default and recommend value, use the long pull way to query consul servers
- `false`, not recommend, it would use the short pull way to query consul servers, then you can set the `fetch_interval` for fetch interval

#### Dump Data

When we need reload `apisix` online, as the `consul` module maybe loads data from CONSUL slower than load routes from ETCD, and would get the log at the moment before load successfully from consul:

```
 http_access_phase(): failed to set upstream: no valid upstream node
```

So, we import the `dump` function for `consul` module. When reload, would load the dump file before from consul; when the registered nodes in consul been updated, would dump the upstream nodes into file automatically.

The `dump` has three optional values now:

- `path`, the dump file save path
    - support relative path, eg: `logs/consul.dump`
    - support absolute path, eg: `/tmp/consul.dump`
    - make sure the dump file's parent path exist
    - make sure the `apisix` has the dump file's read-write access permission,eg: add below config in `conf/config.yaml`

```yaml
nginx_config:                     # config for render the template to generate nginx.conf
  user: root                     # specifies the execution user of the worker process.
```

- `load_on_init`, default value is `true`
    - if `true`, just try to load the data from the dump file before loading data from  consul when starting, does not care the dump file exists or not
    - if `false`, ignore loading data from the dump file
    - Whether `true` or `false`, we don't need to prepare a dump file for apisix at anytime
- `expire`, unit sec, avoiding load expired dump data when load
    - default `0`, it is unexpired forever
    - recommend 2592000, which is 30 days(equals 3600 \* 24 \* 30)

### Register Http API Services

Now, register nodes into consul:

```shell
curl -X PUT 'http://127.0.0.1:8500/v1/agent/service/register' \
-d '{
  "ID": "service_a1",
  "Name": "service_a",
  "Tags": ["primary", "v1"],
  "Address": "127.0.0.1",
  "Port": 8000,
  "Meta": {
    "service_a_version": "4.0"
  },
  "EnableTagOverride": false,
  "Weights": {
    "Passing": 10,
    "Warning": 1
  }
}'

curl -X PUT 'http://127.0.0.1:8500/v1/agent/service/register' \
-d '{
  "ID": "service_a1",
  "Name": "service_a",
  "Tags": ["primary", "v1"],
  "Address": "127.0.0.1",
  "Port": 8002,
  "Meta": {
    "service_a_version": "4.0"
  },
  "EnableTagOverride": false,
  "Weights": {
    "Passing": 10,
    "Warning": 1
  }
}'
```

In some case, same service name exist in different consul servers.
To avoid confusion, use the full consul key url path as service name in practice.

### Upstream setting

#### L7

Here is an example of routing a request with a URL of "/*" to a service which named "service_a" and use consul discovery client in the registry :

```shell
$ curl http://127.0.0.1:9180/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -i -d '
{
    "uri": "/*",
    "upstream": {
        "service_name": "service_a",
        "type": "roundrobin",
        "discovery_type": "consul"
    }
}'
```

The format response as below:

```json
{
  "key": "/apisix/routes/1",
  "value": {
    "uri": "/*",
    "priority": 0,
    "id": "1",
    "upstream": {
      "scheme": "http",
      "type": "roundrobin",
      "hash_on": "vars",
      "discovery_type": "consul",
      "service_name": "service_a",
      "pass_host": "pass"
    },
    "create_time": 1669267329,
    "status": 1,
    "update_time": 1669267329
  }
}
```

You could find more usage in the `apisix/t/discovery/consul.t` file.

#### L4

Consul service discovery also supports use in L4, the configuration method is similar to L7.

```shell
$ curl http://127.0.0.1:9180/apisix/admin/stream_routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -i -d '
{
    "remote_addr": "127.0.0.1",
    "upstream": {
      "scheme": "tcp",
      "service_name": "service_a",
      "type": "roundrobin",
      "discovery_type": "consul"
    }
}'
```

You could find more usage in the `apisix/t/discovery/stream/consul.t` file.

## Debugging API

It also offers control api for debugging.

### Memory Dump API

```shell
GET /v1/discovery/consul/dump
```

For example:

```shell
# curl http://127.0.0.1:9090/v1/discovery/consul/dump | jq
{
  "config": {
    "fetch_interval": 3,
    "timeout": {
      "wait": 60,
      "connect": 6000,
      "read": 6000
    },
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
    "skip_services": [
      "service_d"
    ]
  },
  "services": {
    "service_a": [
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
    "service_b": [
      {
        "host": "172.19.5.51",
        "port": 50051,
        "weight": 1
      }
    ],
    "service_c": [
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

### Show Dump File API

It offers another control api for dump file view now. Maybe would add more api for debugging in future.

```shell
GET /v1/discovery/consul/show_dump_file
```

For example:

```shell
curl http://127.0.0.1:9090/v1/discovery/consul/show_dump_file | jq
{
  "services": {
    "service_a": [
      {
        "host": "172.19.5.12",
        "port": 8000,
        "weight": 120
      },
      {
        "host": "172.19.5.13",
        "port": 8000,
        "weight": 120
      }
    ]
  },
  "expire": 0,
  "last_update": 1615877468
}
```
