---
title: FAQ
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

## Why a new API gateway?

There are new requirements for API gateways in the field of microservices: higher flexibility, higher performance requirements, and cloud native.

## What are the differences between Apache APISIX and other API gateways?

Apache APISIX is based on etcd to save and synchronize configuration, not relational databases such as Postgres or MySQL.

This not only eliminates polling, makes the code more concise, but also makes configuration synchronization more real-time. At the same time, there will be no single point in the system, which is more usable.

In addition, Apache APISIX has dynamic routing and hot loading of plug-ins, which is especially suitable for API management under micro-service system.

## What's the performance of Apache APISIX?

One of the goals of Apache APISIX design and development is the highest performance in the industry. Specific test data can be found here：[benchmark](benchmark.md)

Apache APISIX is the highest performance API gateway with a single-core QPS of 23,000, with an average delay of only 0.6 milliseconds.

## Does Apache APISIX have a user interface？

Yes. Apache APISIX has an experimental feature called [Apache APISIX Dashboard](https://github.com/apache/apisix-dashboard), which is an independent project apart from Apache APISIX. You can deploy Apache APISIX Dashboard to operate Apache APISIX through the user interface.

## Can I write my own plugin?

Of course, Apache APISIX provides flexible custom plugins for developers and businesses to write their own logic.

[How to write plugin](plugin-develop.md)

## Why we choose etcd as the configuration center?

For the configuration center, configuration storage is only the most basic function, and Apache APISIX also needs the following features:

1. Cluster
2. Transactions
3. Multi-version Concurrency Control
4. Change Notification
5. High Performance

See more [etcd why](https://github.com/etcd-io/website/blob/master/content/en/docs/next/learning/why.md#comparison-chart).

## Why is it that installing Apache APISIX dependencies with Luarocks causes timeout, slow or unsuccessful installation?

There are two possibilities when encountering slow luarocks:

1. Server used for luarocks installation is blocked
2. There is a place between your network and github server to block the 'git' protocol

For the first problem, you can use https_proxy or use the `--server` option to specify a luarocks server that you can access or access faster.
Run the `luarocks config rocks_servers` command(this command is supported after luarocks 3.0) to see which server are available.
For China mainland users, you can use the `luarocks.cn` as the luarocks server.

We already provide a wrapper in the Makefile to simplify your job:

```bash
LUAROCKS_SERVER=https://luarocks.cn make deps
```

If using a proxy doesn't solve this problem, you can add `--verbose` option during installation to see exactly how slow it is. Excluding the first case, only the second that the `git` protocol is blocked. Then we can run `git config --global url."https://".insteadOf git://` to using the 'HTTPS' protocol instead of `git`.

## How to support gray release via Apache APISIX?

An example, `foo.com/product/index.html?id=204&page=2`, gray release based on `id` in the query string in URL as a condition：

1. Group A：id <= 1000
2. Group B：id > 1000

There are two different ways to do this：

1. Use the `vars` field of route to do it.

```shell
curl -i http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/index.html",
    "vars": [
        ["arg_id", "<=", "1000"]
    ],
    "plugins": {
        "redirect": {
            "uri": "/test?group_id=1"
        }
    }
}'

curl -i http://127.0.0.1:9080/apisix/admin/routes/2 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/index.html",
    "vars": [
        ["arg_id", ">", "1000"]
    ],
    "plugins": {
        "redirect": {
            "uri": "/test?group_id=2"
        }
    }
}'
```

Here is the operator list of current `lua-resty-radixtree`：
https://github.com/iresty/lua-resty-radixtree#operator-list

2. Use `traffic-split` plugin to do it.

Please refer to the [traffic-split.md](plugins/traffic-split.md) plugin documentation for usage examples.

## How to redirect http to https via Apache APISIX?

An example, redirect `http://foo.com` to `https://foo.com`

There are several different ways to do this.

1. Directly use the `http_to_https` in `redirect` plugin：

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/hello",
    "host": "foo.com",
    "plugins": {
        "redirect": {
            "http_to_https": true
        }
    }
}'
```

2. Use with advanced routing rule `vars` with `redirect` plugin:

```shell
curl -i http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/hello",
    "host": "foo.com",
    "vars": [
        [
            "scheme",
            "==",
            "http"
        ]
    ],
    "plugins": {
        "redirect": {
            "uri": "https://$host$request_uri",
            "ret_code": 301
        }
    }
}'
```

3. `serverless` plugin：

```shell
curl -i http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/hello",
    "plugins": {
        "serverless-pre-function": {
            "phase": "rewrite",
            "functions": ["return function() if ngx.var.scheme == \"http\" and ngx.var.host == \"foo.com\" then ngx.header[\"Location\"] = \"https://foo.com\" .. ngx.var.request_uri; ngx.exit(ngx.HTTP_MOVED_PERMANENTLY); end; end"]
        }
    }
}'
```

Then test it to see if it works：

```shell
curl -i -H 'Host: foo.com' http://127.0.0.1:9080/hello
```

The response body should be:

```
HTTP/1.1 301 Moved Permanently
Date: Mon, 18 May 2020 02:56:04 GMT
Content-Type: text/html
Content-Length: 166
Connection: keep-alive
Location: https://foo.com/hello
Server: APISIX web server

<html>
<head><title>301 Moved Permanently</title></head>
<body>
<center><h1>301 Moved Permanently</h1></center>
<hr><center>openresty</center>
</body>
</html>
```

## How to change the log level?

The default log level for Apache APISIX is `warn`. However You can change the log level to `info` if you want to trace the messages print by `core.log.info`.

Steps:

1. Modify the parameter `error_log_level: "warn"` to `error_log_level: "info"` in conf/config.yaml.

```yaml
nginx_config:
  error_log_level: "info"
```

2. Reload or restart Apache APISIX

Now you can trace the info level log in logs/error.log.

## How to reload your own plugin?

The Apache APISIX plugin supports hot reloading.
See the `Hot reload` section in [plugins](./plugins.md) for how to do that.

## How to make Apache APISIX listen on multiple ports when handling HTTP or HTTPS requests?

By default, Apache APISIX only listens on port 9080 when handling HTTP requests. If you want Apache APISIX to listen on multiple ports, you need to modify the relevant parameters in the configuration file as follows:

1. Modify the parameter of HTTP port listen `node_listen` in `conf/config.yaml`, for example:

   ```
    apisix:
      node_listen:
        - 9080
        - 9081
        - 9082
   ```

   Handling HTTPS requests is similar, modify the parameter of HTTPS port listen `ssl.listen_port` in `conf/config.yaml`, for example:

    ```
    apisix:
      ssl:
        listen_port:
          - 9443
          - 9444
          - 9445
    ```

2. Reload or restart Apache APISIX

## How does Apache APISIX use etcd to achieve millisecond-level configuration synchronization

etcd provides subscription functions to monitor whether the specified keyword or directory is changed (for example: [watch](https://github.com/api7/lua-resty-etcd/blob/master/api_v3.md#watch), [watchdir](https://github.com/api7/lua-resty-etcd/blob/master/api_v3.md#watchdir)).

Apache APISIX uses [etcd.watchdir](https://github.com/api7/lua-resty-etcd/blob/master/api_v3.md#watchdir) to monitor directory content changes:

* If there is no data update in the monitoring directory: the process will be blocked until timeout or other errors occurred.
* If the monitoring directory has data updates: etcd will return the new subscribed data immediately (in milliseconds), and Apache APISIX will update it to the memory cache.

With the help of etcd which incremental notification feature is millisecond-level, Apache APISIX achieve millisecond-level of configuration synchronization.

## How to customize the Apache APISIX instance id?

By default, Apache APISIX will read the instance id from `conf/apisix.uid`. If it is not found, and no id is configured, Apache APISIX will generate a `uuid` as the instance id.

If you want to specify a meaningful id to bind Apache APISIX instance to your internal system, you can configure it in `conf/config.yaml`, for example:

    ```
    apisix:
      id: "your-meaningful-id"
    ```

## Why there are a lot of "failed to fetch data from etcd, failed to read etcd dir, etcd key: xxxxxx" errors in error.log?

First please make sure the network between Apache APISIX and etcd cluster is not partitioned.

If the network is healthy, please check whether your etcd cluster enables the [gRPC gateway](https://etcd.io/docs/v3.4.0/dev-guide/api_grpc_gateway/).  However, The default case for this feature is different when use command line options or configuration file to start etcd server.

1. When command line options is in use, this feature is enabled by default, the related option is `--enable-grpc-gateway`.

```sh
etcd --enable-grpc-gateway --data-dir=/path/to/data
```

Note this option is not shown in the output of `etcd --help`.

2. When configuration file is used, this feature is disabled by default, please enable `enable-grpc-gateway` explicitly.

```json
# etcd.json
{
    "enable-grpc-gateway": true,
    "data-dir": "/path/to/data"
}
```

```yml
# etcd.conf.yml
enable-grpc-gateway: true
```

Indeed this distinction was eliminated by etcd in their master branch, but not backport to announced versions, so be care when deploy your etcd cluster.

## How to set up high available Apache APISIX clusters?

The high availability of Apache APISIX can be divided into two parts:

1. The data plane of Apache APISIX is stateless and can be elastically scaled at will. Just add a layer of LB in front.

2. The control plane of Apache APISIX relies on the highly available implementation of `etcd cluster` and does not require any relational database dependency.

## Why does the `make deps` command fail in source installation?

When executing the `make deps` command, an error such as the one shown below occurs. This is caused by the missing openresty's `openssl` development kit, you need to install it first. Please refer to the [install dependencies](install-dependencies.md) document for installation.

```shell
$ make deps
......
Error: Failed installing dependency: https://luarocks.org/luasec-0.9-1.src.rock - Could not find header file for OPENSSL
  No file openssl/ssl.h in /usr/local/include
You may have to install OPENSSL in your system and/or pass OPENSSL_DIR or OPENSSL_INCDIR to the luarocks command.
Example: luarocks install luasec OPENSSL_DIR=/usr/local
make: *** [deps] Error 1
```

## How to access Apache APISIX Dashboard through Apache APISIX proxy

1. Keep the Apache APISIX proxy port and Admin API port different(or disable Admin API). For example, do the following configuration in `conf/config.yaml`.

The Admin API use a separate port 9180:

```yaml
apisix:
  port_admin: 9180            # use a separate port
```

2. Add proxy route of Apache APISIX Dashboard:

Note: The Apache APISIX Dashboard service here is listening on `127.0.0.1:9000`.

```shell
curl -i http://127.0.0.1:9180/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uris":[ "/*" ],
    "name":"apisix_proxy_dashboard",
    "upstream":{
        "nodes":[
            {
                "host":"127.0.0.1",
                "port":9000,
                "weight":1
            }
        ],
        "type":"roundrobin"
    }
}'
```

## How to use route `uri` for regular matching

The regular matching of uri is achieved through the `vars` field of route.

```shell
curl -i http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/*",
    "vars": [
        ["uri", "~~", "^/[a-z]+$"]
    ],
    "upstream": {
            "type": "roundrobin",
            "nodes": {
                "127.0.0.1:1980": 1
            }
    }
}'
```

Test request:

```shell
# The uri matched successfully
$ curl http://127.0.0.1:9080/hello -i
HTTP/1.1 200 OK
...

# The uri match failed
$ curl http://127.0.0.1:9080/12ab -i
HTTP/1.1 404 Not Found
...
```

In route, we can achieve more condition matching by combining `uri` with `vars` field. For more details of using `vars`, please refer to [lua-resty-expr](https://github.com/api7/lua-resty-expr).

## Does the upstream node support configuring the [FQDN](https://en.wikipedia.org/wiki/Fully_qualified_domain_name) address

This is supported. Here is an example where the `FQDN` is `httpbin.default.svc.cluster.local`:

This is supported. Here is an example where the `FQDN` is `httpbin.default.svc.cluster.local` (a Kubernetes Service):

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/ip",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "httpbin.default.svc.cluster.local": 1
        }
    }
}'
```

```shell
# Test request
$ curl http://127.0.0.1:9080/ip -i
HTTP/1.1 200 OK
...
```

## What is the `X-API-KEY` of Admin API? Can it be modified?

1. The `X-API-KEY` of Admin API refers to the `apisix.admin_key.key` in the `config.yaml` file, and the default value is `edd1c9f034335f136f87ad84b625c8f1`. It is the access token of the Admin API.

Note: There are security risks in using the default API token. It is recommended to update it when deploying to a production environment.

2. `X-API-KEY` can be modified.

For example: make the following changes to the `apisix.admin_key.key` in the `conf/config.yaml` file and reload Apache APISIX.

```yaml
apisix:
  admin_key
    -
      name: "admin"
      key: abcdefghabcdefgh
      role: admin
```

Access the Admin API:

```shell
$ curl -i http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: abcdefghabcdefgh' -X PUT -d '
{
    "uris":[ "/*" ],
    "name":"admin-token-test",
    "upstream":{
        "nodes":[
            {
                "host":"127.0.0.1",
                "port":1980,
                "weight":1
            }
        ],
        "type":"roundrobin"
    }
}'

HTTP/1.1 200 OK
......
```

The route was created successfully. It means that the modification of `X-API-KEY` takes effect.

## How to allow all IPs to access Admin API

By default, Apache APISIX only allows the IP range of `127.0.0.0/24` to access the `Admin API`. If you want to allow all IP access, then you only need to add the following configuration in the `conf/config.yaml` configuration file.

```yaml
apisix:
  allow_admin:
    - 0.0.0.0/0
```

Restart or reload Apache APISIX, all IPs can access the `Admin API`.

**Note: You can use this method in a non-production environment to allow all clients from anywhere to access your `Apache APISIX` instances, but it is not safe to use it in a production environment. In production environment, please only authorize specific IP addresses or address ranges to access your instance.**

## How to auto renew SSL cert via acme.sh

```bash
$ curl --output /root/.acme.sh/renew-hook-update-apisix.sh --silent https://gist.githubusercontent.com/anjia0532/9ebf8011322f43e3f5037bc2af3aeaa6/raw/65b359a4eed0ae990f9188c2afa22bacd8471652/renew-hook-update-apisix.sh

$ chmod +x /root/.acme.sh/renew-hook-update-apisix.sh

$ acme.sh  --issue  --staging  -d demo.domain --renew-hook "/root/.acme.sh/renew-hook-update-apisix.sh  -h http://apisix-admin:port -p /root/.acme.sh/demo.domain/demo.domain.cer -k /root/.acme.sh/demo.domain/demo.domain.key -a xxxxxxxxxxxxx"

$ acme.sh --renew --domain demo.domain

```

Blog https://juejin.cn/post/6965778290619449351 has detail setup.

## How to strip route prefix for path matching

To strip route prefix before forwarding to upstream, for example from `/foo/get` to `/get`, could be achieved through plugin `proxy-rewrite`.

```shell
curl -i http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/foo/*",
    "plugins": {
        "proxy-rewrite": {
            "regex_uri": ["^/foo/(.*)","/$1"]
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "httpbin.org:80": 1
        }
    }
}'
```

Test request:

```shell
$ curl http://127.0.0.1:9080/foo/get -i
HTTP/1.1 200 OK
...
{
  ...
  "url": "http://127.0.0.1/get"
}
```
