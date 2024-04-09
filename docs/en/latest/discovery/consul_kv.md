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

For users that are using [nginx-upsync-module](https://github.com/weibocom/nginx-upsync-module) and Consul KV as a service discovery, like the Weibo Mobile Team, this may be needed.

Thanks to @fatman-x guy, who developed this module, called `consul_kv`, and its worker process data flow is below:
![consul kv module data flow diagram](https://user-images.githubusercontent.com/548385/107141841-6ced3e00-6966-11eb-8aa4-bc790a4ad113.png)

## Configuration for discovery client

### Configuration for Consul KV

Add following configuration in `conf/config.yaml` :

```yaml
discovery:
  consul_kv:
    servers:
      - "http://127.0.0.1:8500"
      - "http://127.0.0.1:8600"
    token: "..."                  # if your consul cluster has enabled acl access control, you need to specify the token
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
    dump:                         # if you need, when registered nodes updated can dump into file
       path: "logs/consul_kv.dump"
       expire: 2592000      # unit sec, here is 30 day
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

#### Dump Data

When we need reload `apisix` online, as the `consul_kv` module maybe loads data from CONSUL slower than load routes from ETCD, and would get the log at the moment before load successfully from consul:

```
 http_access_phase(): failed to set upstream: no valid upstream node
```

So, we import the `dump` function for `consul_kv` module. When reload, would load the dump file before from consul; when the registered nodes in consul been updated, would dump the upstream nodes into file automatically.

The `dump` has three optional values now:

- `path`, the dump file save path
    - support relative path, eg: `logs/consul_kv.dump`
    - support absolute path, eg: `/tmp/consul_kv.bin`
    - make sure the dump file's parent path exist
    - make sure the `apisix` has the dump file's read-write access permission,eg: `chown  www:root conf/upstream.d/`
- `load_on_init`, default value is `true`
    - if `true`, just try to load the data from the dump file before loading data from  consul when starting, does not care the dump file exists or not
    - if `false`, ignore loading data from the dump file
    - Whether `true` or `false`, we don't need to prepare a dump file for apisix at anytime
- `expire`, unit sec, avoiding load expired dump data when load
    - default `0`, it is unexpired forever
    - recommend 2592000, which is 30 days(equals 3600 \* 24 \* 30)

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

#### L7

Here is an example of routing a request with a URL of "/*" to a service which named "http://127.0.0.1:8500/v1/kv/upstreams/webpages/" and use consul_kv discovery client in the registry :

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
$ curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -i -d '
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
  }
}
```

You could find more usage in the `apisix/t/discovery/consul_kv.t` file.

#### L4

Consul_kv service discovery also supports use in L4, the configuration method is similar to L7.

```shell
$ curl http://127.0.0.1:9180/apisix/admin/stream_routes/1 -H "X-API-KEY: $admin_key" -X PUT -i -d '
{
    "remote_addr": "127.0.0.1",
    "upstream": {
      "scheme": "tcp",
      "service_name": "http://127.0.0.1:8500/v1/kv/upstreams/webpages/",
      "type": "roundrobin",
      "discovery_type": "consul_kv"
    }
}'
```

You could find more usage in the `apisix/t/discovery/stream/consul_kv.t` file.

## Debugging API

It also offers control api for debugging.

### Memory Dump API

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

### Show Dump File API

It offers another control api for dump file view now. Maybe would add more api for debugging in future.

```shell
GET /v1/discovery/consul_kv/show_dump_file
```

For example:

```shell
curl http://127.0.0.1:9090/v1/discovery/consul_kv/show_dump_file | jq
{
  "services": {
    "http://172.19.5.31:8500/v1/kv/upstreams/1614480/webpages/": [
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
