---
title: FAQ
keywords:
  - Apache APISIX
  - API Gateway
  - FAQ
description: This article lists solutions to common problems when using Apache APISIX.
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

## Why do I need a new API gateway?

As organizations move towards cloud native microservices, there is a need for an API gateway that is performant, flexible, secure and scalable.

APISIX outperforms other API gateways in these metrics while being platform agnostic and fully dynamic delivering features like supporting multiple protocols, fine-grained routing and multi-language support.

## How does Apache APISIX differ from other API gateways?

Apache APISIX differs in the following ways:

- It uses etcd to save and synchronize configurations rather than relational databases like PostgreSQL or MySQL. The real-time event notification system in etcd is easier to scale than in these alternatives. This allows APISIX to synchronize the configuration in real-time, makes the code concise and avoids a single point of failure.
- Fully dynamic.
- Supports [hot loading of Plugins](./terminology/plugin.md#hot-reload).

## What is the performance impact of using Apache APISIX?

Apache APISIX delivers the best performance among other API gateways with a single-core QPS of 18,000 with an average delay of 0.2 ms.

Specific results of the performance benchmarks can be found [here](benchmark.md).

## Which platforms does Apache APISIX support?

Apache APISIX is platform agnostic and avoids vendor lock-in. It is built for cloud native environments and can run on bare-metal machines to Kubernetes. It even support Apple Silicon chips.

## What does it mean by "Apache APISIX is fully dynamic"?

Apache APISIX is fully dynamic in the sense that it doesn't require restarts to change its behavior.

It does the following dynamically:

- Reloading Plugins
- Proxy rewrites
- Proxy mirror
- Response rewrites
- Health checks
- Traffic split

## Does Apache APISIX have a user interface?

APISIX has a powerful built-in Dashboard [APISIX Dashboard](https://github.com/apache/apisix-dashboard). You can manage APISIX configurations through the [APISIX Dashboard](https://github.com/apache/apisix-dashboard) user interface.

## Can I write my own Plugins for Apache APISIX?

Yes. Apache APISIX is flexible and extensible through the use of custom Plugins that can be specific to user needs.

You can write your own Plugins by referring to [How to write your own Plugins](plugin-develop.md).

## Why does Apache APISIX use etcd for the configuration center?

In addition to the basic functionality of storing the configurations, Apache APISIX also needs a storage system that supports these features:

1. Distributed deployments in clusters.
2. Guarded transactions by comparisons.
3. Multi-version concurrency control.
4. Notifications and watch streams.
5. High performance with minimum read/write latency.

etcd provides these features and more making it ideal over other databases like PostgreSQL and MySQL.

To learn more on how etcd compares with other alternatives see this [comparison chart](https://etcd.io/docs/latest/learning/why/#comparison-chart).

## When installing Apache APISIX dependencies with LuaRocks, why does it cause a timeout or result in a slow or unsuccessful installation?

This is likely because the LuaRocks server used is blocked.

To solve this you can use https_proxy or use the `--server` flag to specify a faster LuaRocks server.

You can run the command below to see the available servers (needs LuaRocks 3.0+):

```shell
luarocks config rocks_servers
```

Mainland China users can use `luarocks.cn` as the LuaRocks server. You can use this wrapper with the Makefile to set this up:

```bash
make deps ENV_LUAROCKS_SERVER=https://luarocks.cn
```

If this does not solve your problem, you can try getting a detailed log by using the `--verbose` or `-v` flag to diagnose the problem.

## How do I build the APISIX-Runtime environment?

Some functions need to introduce additional NGINX modules, which requires APISIX to run on APISIX-Runtime. If you need these functions, you can refer to the code in [api7/apisix-build-tools](https://github.com/api7/apisix-build-tools) to build your own APISIX-Runtime environment.

## How can I make a gray release with Apache APISIX?

Let's take an example query `foo.com/product/index.html?id=204&page=2` and consider that you need to make a gray release based on the `id` in the query string with this condition:

1. Group A: `id <= 1000`
2. Group B: `id > 1000`

There are two different ways to achieve this in Apache APISIX:

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

1. Using the `vars` field in a [Route](terminology/route.md):

```shell
curl -i http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
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

curl -i http://127.0.0.1:9180/apisix/admin/routes/2 -H "X-API-KEY: $admin_key" -X PUT -d '
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

All the available operators of the current `lua-resty-radixtree` are listed [here](https://github.com/api7/lua-resty-radixtree#operator-list).

2. Using the [traffic-split](plugins/traffic-split.md) Plugin.

## How do I redirect HTTP traffic to HTTPS with Apache APISIX?

For example, you need to redirect traffic from `http://foo.com` to `https://foo.com`.

Apache APISIX provides several different ways to achieve this:

1. Setting `http_to_https` to `true` in the [redirect](plugins/redirect.md) Plugin:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  -H "X-API-KEY: $admin_key" -X PUT -d '
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

2. Advanced routing with `vars` in the redirect Plugin:

```shell
curl -i http://127.0.0.1:9180/apisix/admin/routes/1  -H "X-API-KEY: $admin_key" -X PUT -d '
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

3. Using the `serverless` Plugin:

```shell
curl -i http://127.0.0.1:9180/apisix/admin/routes/1  -H "X-API-KEY: $admin_key" -X PUT -d '
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

To test this serverless Plugin:

```shell
curl -i -H 'Host: foo.com' http://127.0.0.1:9080/hello
```

The response should be:

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

## How do I change Apache APISIX's log level?

By default the log level of Apache APISIX is set to `warn`. You can set this to `info` to trace the messages printed by `core.log.info`.

For this, you can set the `error_log_level` parameter in your configuration file (conf/config.yaml) as shown below and reload Apache APISIX.

```yaml
nginx_config:
  error_log_level: "info"
```

## How do I reload my custom Plugins for Apache APISIX?

All Plugins in Apache APISIX are hot reloaded.

You can learn more about hot reloading of Plugins [here](./terminology/plugin.md#hot-reload).

## How do I configure Apache APISIX to listen on multiple ports when handling HTTP or HTTPS requests?

By default, Apache APISIX listens only on port 9080 when handling HTTP requests.

To configure Apache APISIX to listen on multiple ports, you can:

1. Modify the parameter `node_listen` in `conf/config.yaml`:

   ```
    apisix:
      node_listen:
        - 9080
        - 9081
        - 9082
   ```

   Similarly for HTTPS requests, modify the parameter `ssl.listen` in `conf/config.yaml`:

   ```
   apisix:
     ssl:
       enable: true
       listen:
         - port: 9443
         - port: 9444
         - port: 9445
   ```

2. Reload or restart Apache APISIX.

## After uploading the SSL certificate, why can't the corresponding route be accessed through HTTPS + IP?

If you directly use HTTPS + IP address to access the server, the server will use the IP address to compare with the bound SNI. Since the SSL certificate is bound to the domain name, the corresponding resource cannot be found in the SNI, so that the certificate will be verified. The authentication fails, and the user cannot access the gateway via HTTPS + IP.

You can implement this function by setting the `fallback_sni` parameter in the configuration file and configuring the domain name. When the user uses HTTPS + IP to access the gateway, when the SNI is empty, it will fall back to the default SNI to achieve HTTPS + IP access to the gateway.

```yaml title="./conf/config.yaml"
apisix
  ssl：
    fallback_sni: "${your sni}"
```

## How does Apache APISIX achieve millisecond-level configuration synchronization?

Apache APISIX uses etcd for its configuration center. etcd provides subscription functions like [watch](https://github.com/api7/lua-resty-etcd/blob/master/api_v3.md#watch) and [watchdir](https://github.com/api7/lua-resty-etcd/blob/master/api_v3.md#watchdir) that can monitor changes to specific keywords or directories.

In Apache APISIX, we use [etcd.watchdir](https://github.com/api7/lua-resty-etcd/blob/master/api_v3.md#watchdir) to monitor changes in a directory.

If there is no change in the directory being monitored, the process will be blocked until it times out or run into any errors.

If there are changes in the directory being monitored, etcd will return this new data within milliseconds and Apache APISIX will update the cache memory.

## How do I customize the Apache APISIX instance id?

By default, Apache APISIX reads the instance id from `conf/apisix.uid`. If this is not found and no id is configured, Apache APISIX will generate a `uuid` for the instance id.

To specify a meaningful id to bind Apache APISIX to your internal system, set the `id` in your `conf/config.yaml` file:

```yaml
apisix:
  id: "your-id"
```

## Why are there errors saying "failed to fetch data from etcd, failed to read etcd dir, etcd key: xxxxxx" in the error.log?

Please follow the troubleshooting steps described below:

1. Make sure that there aren't any networking issues between Apache APISIX and your etcd deployment in your cluster.
2. If your network is healthy, check whether you have enabled the [gRPC gateway](https://etcd.io/docs/v3.4/dev-guide/api_grpc_gateway/) for etcd. The default state depends on whether you used command line options or a configuration file to start the etcd server.

   - If you used command line options, gRPC gateway is enabled by default. You can enable it manually as shown below:

   ```sh
   etcd --enable-grpc-gateway --data-dir=/path/to/data
   ```

   **Note**: This flag is not shown while running `etcd --help`.

   - If you used a configuration file, gRPC gateway is disabled by default. You can manually enable it as shown below:

   In `etcd.json`:

   ```json
   {
     "enable-grpc-gateway": true,
     "data-dir": "/path/to/data"
   }
   ```

   In `etcd.conf.yml`:

   ```yml
   enable-grpc-gateway: true
   ```

**Note**: This distinction was eliminated by etcd in their latest master branch but wasn't backported to previous versions.

## How do I setup high availability Apache APISIX clusters?

Apache APISIX can be made highly available by adding a load balancer in front of it as APISIX's data plane is stateless and can be scaled when needed.

The control plane of Apache APISIX is highly available as it relies only on an etcd cluster.

## Why does the `make deps` command fail when installing Apache APISIX from source?

When executing `make deps` to install Apache APISIX from source, you can get an error as shown below:

```shell
$ make deps
......
Error: Failed installing dependency: https://luarocks.org/luasec-0.9-1.src.rock - Could not find header file for OPENSSL
  No file openssl/ssl.h in /usr/local/include
You may have to install OPENSSL in your system and/or pass OPENSSL_DIR or OPENSSL_INCDIR to the luarocks command.
Example: luarocks install luasec OPENSSL_DIR=/usr/local
make: *** [deps] Error 1
```

This is caused by the missing OpenResty openssl development kit. To install it, refer [installing dependencies](install-dependencies.md).

## How do I use regular expressions (regex) for matching `uri` in a Route?

You can use the `vars` field in a Route for matching regular expressions:

```shell
curl -i http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
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

And to test this request:

```shell
# uri matched
$ curl http://127.0.0.1:9080/hello -i
HTTP/1.1 200 OK
...

# uri didn't match
$ curl http://127.0.0.1:9080/12ab -i
HTTP/1.1 404 Not Found
...
```

For more info on using `vars` refer to [lua-resty-expr](https://github.com/api7/lua-resty-expr).

## Does the Upstream node support configuring a [FQDN](https://en.wikipedia.org/wiki/Fully_qualified_domain_name) address?

Yes. The example below shows configuring the FQDN `httpbin.default.svc.cluster.local` (a Kubernetes service):

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  -H "X-API-KEY: $admin_key" -X PUT -d '
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

To test this Route:

```shell
$ curl http://127.0.0.1:9080/ip -i
HTTP/1.1 200 OK
...
```

## What is the `X-API-KEY` of the Admin API? Can it be modified?

`X-API-KEY` of the Admin API refers to the `apisix.admin_key.key` in your `conf/config.yaml` file. It is the access token for the Admin API.

By default, it is set to `edd1c9f034335f136f87ad84b625c8f1` and can be modified by changing the parameter in your `conf/config.yaml` file:

```yaml
apisix:
  admin_key
    -
      name: "admin"
      key: newkey
      role: admin
```

Now, to access the Admin API:

```shell
$ curl -i http://127.0.0.1:9180/apisix/admin/routes/1  -H 'X-API-KEY: newkey' -X PUT -d '
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

**Note**: By using the default token, you could be exposed to security risks. It is required to update it when deploying to a production environment.

## How do I allow all IPs to access Apache APISIX's Admin API?

By default, Apache APISIX only allows IPs in the range `127.0.0.0/24` to access the Admin API.

To allow IPs in all ranges, you can update your configuration file as show below and restart or reload Apache APISIX.

```yaml
deployment:
  admin:
    allow_admin:
      - 0.0.0.0/0
```

**Note**: This should only be used in non-production environments to allow all clients to access Apache APISIX and is not safe for production environments. Always authorize specific IP addresses or address ranges for production environments.

## How do I auto renew SSL certificates with acme.sh?

You can run the commands below to achieve this:

```bash
curl --output /root/.acme.sh/renew-hook-update-apisix.sh --silent https://gist.githubusercontent.com/anjia0532/9ebf8011322f43e3f5037bc2af3aeaa6/raw/65b359a4eed0ae990f9188c2afa22bacd8471652/renew-hook-update-apisix.sh
```

```bash
chmod +x /root/.acme.sh/renew-hook-update-apisix.sh
```

```bash
acme.sh  --issue  --staging  -d demo.domain --renew-hook "/root/.acme.sh/renew-hook-update-apisix.sh  -h http://apisix-admin:port -p /root/.acme.sh/demo.domain/demo.domain.cer -k /root/.acme.sh/demo.domain/demo.domain.key -a xxxxxxxxxxxxx"
```

```bash
acme.sh --renew --domain demo.domain
```

You can check [this post](https://juejin.cn/post/6965778290619449351) for a more detailed instruction on setting this up.

## How do I strip a prefix from a path before forwarding to Upstream in Apache APISIX?

To strip a prefix from a path in your route, like to take `/foo/get` and strip it to `/get`, you can use the [proxy-rewrite](plugins/proxy-rewrite.md) Plugin:

```shell
curl -i http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
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

And to test this configuration:

```shell
curl http://127.0.0.1:9080/foo/get -i
HTTP/1.1 200 OK
...
{
  ...
  "url": "http://127.0.0.1/get"
}
```

## How do I fix the error `unable to get local issuer certificate` in Apache APISIX?

You can manually set the path to your certificate by adding it to your `conf/config.yaml` file as shown below:

```yaml
apisix:
  ssl:
    ssl_trusted_certificate: /path/to/certs/ca-certificates.crt
```

**Note**: When you are trying to connect TLS services with cosocket and if APISIX does not trust the peer's TLS certificate, you should set the parameter `apisix.ssl.ssl_trusted_certificate`.

For example, if you are using Nacos for service discovery in APISIX, and Nacos has TLS enabled (configured host starts with `https://`), you should set `apisix.ssl.ssl_trusted_certificate` and use the same CA certificate as Nacos.

## How do I fix the error `module 'resty.worker.events' not found` in Apache APISIX?

This error is caused by installing Apache APISIX in the `/root` directory. The worker process would by run by the user "nobody" and it would not have enough permissions to access the files in the `/root` directory.

To fix this, you can change the APISIX installation directory to the recommended directory: `/usr/local`.

## What is the difference between `plugin-metadata` and `plugin-configs` in Apache APISIX?

The differences between the two are described in the table below:

| `plugin-metadata`                                                                                                | `plugin-config`                                                                                                                                     |
| ---------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| Metadata of a Plugin shared by all configuration instances of the Plugin.                                        | Collection of configuration instances of multiple different Plugins.                                                                                |
| Used when there are property changes that needs to be propagated across all configuration instances of a Plugin. | Used when you need to reuse a common set of configuration instances so that it can be extracted to a `plugin-config` and bound to different Routes. |
| Takes effect on all the entities bound to the configuration instances of the Plugin.                             | Takes effect on Routes bound to the `plugin-config`.                                                                                                |

## After deploying Apache APISIX, how to detect the survival of the APISIX data plane?

You can create a route named `health-info` and enable the [fault-injection](https://apisix.apache.org/docs/apisix/plugins/fault-injection/) plugin (where YOUR-TOKEN is the user's token; 127.0.0.1 is the IP address of the control plane, which can be modified by yourself):

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/health-info \
-H 'X-API-KEY: YOUR-TOKEN' -X PUT -d '
{
   "plugins": {
     "fault-injection": {
       "abort": {
        "http_status": 200,
        "body": "fine"
       }
     }
   },
   "uri": "/status"
}'
````

Verification:

Access the `/status` of the Apache APISIX data plane to detect APISIX. If the response code is 200, it means APISIX is alive.

:::note

This method only detects whether the APISIX data plane is alive or not. It does not mean that the routing and other functions of APISIX are normal. These require more routing-level detection.

:::

## What are the scenarios with high APISIX latency related to [etcd](https://etcd.io/) and how to fix them?

etcd is the data storage component of apisix, and its stability is related to the stability of APISIX.

In actual scenarios, if APISIX uses a certificate to connect to etcd through HTTPS, the following two problems of high latency for data query or writing may occur:

1. Query or write data through APISIX Admin API.
2. In the monitoring scenario, Prometheus crawls the APISIX data plane Metrics API timeout.

These problems related to higher latency seriously affect the service stability of APISIX, and the reason why such problems occur is mainly because etcd provides two modes of operation: HTTP (HTTPS) and gRPC. And APISIX uses the HTTP (HTTPS) protocol to operate etcd by default.
In this scenario, etcd has a bug about HTTP/2: if etcd is operated over HTTPS (HTTP is not affected), the upper limit of HTTP/2 connections is the default `250` in Golang. Therefore, when the number of APISIX data plane nodes is large, once the number of connections between all APISIX nodes and etcd exceeds this upper limit, the response of APISIX API interface will be very slow.

In Golang, the default upper limit of HTTP/2 connections is `250`, the code is as follows:

```go
package http2

import ...

const (
    prefaceTimeout         = 10 * time.Second
    firstSettingsTimeout   = 2 * time.Second // should be in-flight with preface anyway
    handlerChunkWriteSize  = 4 << 10
    defaultMaxStreams      = 250 // TODO: make this 100 as the GFE seems to?
    maxQueuedControlFrames = 10000
)

```

etcd officially maintains two main branches, `3.4` and `3.5`. In the `3.4` series, the recently released `3.4.20` version has fixed this issue. As for the `3.5` version, the official is preparing to release the `3.5.5` version a long time ago, but it has not been released as of now (2022.09.13). So, if you are using etcd version less than `3.5.5`, you can refer to the following ways to solve this problem:

1. Change the communication method between APISIX and etcd from HTTPS to HTTP.
2. Roll back the etcd to `3.4.20`.
3. Clone the etcd source code and compile the `release-3.5` branch directly (this branch has fixed the problem of HTTP/2 connections, but the new version has not been released yet).

The way to recompile etcd is as follows:

```shell
git checkout release-3.5
make GOOS=linux GOARCH=amd64
```

The compiled binary is in the bin directory, replace it with the etcd binary of your server environment, and then restart etcd:

For more information, please refer to:

- [when etcd node have many http long polling connections, it may cause etcd to respond slowly to http requests.](https://github.com/etcd-io/etcd/issues/14185)
- [bug: when apisix starts for a while, its communication with etcd starts to time out](https://github.com/apache/apisix/issues/7078)
- [the prometheus metrics API is tool slow](https://github.com/apache/apisix/issues/7353)
- [Support configuring `MaxConcurrentStreams` for http2](https://github.com/etcd-io/etcd/pull/14169)

Another solution is to switch to an experimental gRPC-based configuration synchronization. This requires setting `use_grpc: true` in the configuration file `conf/config.yaml`:

```yaml
  etcd:
    use_grpc: true
    host:
      - "http://127.0.0.1:2379"
    prefix: "/apisix"
```

## Why is the file-logger logging garbled?

If you are using the `file-logger` plugin but getting garbled logs, one possible reason is your upstream response has returned a compressed response body. You can fix this by setting the accept-encoding in the request header to not receive compressed responses using the [proxy-rewirte](https://apisix.apache.org/docs/apisix/plugins/proxy-rewrite/) plugin:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H 'X-API-KEY: YOUR-TOKEN' -X PUT -d '
{
    "methods":[
        "GET"
    ],
    "uri":"/test/index.html",
    "plugins":{
        "proxy-rewrite":{
            "headers":{
                "set":{
                    "accept-encoding":"gzip;q=0,deflate,sdch"
                }
            }
        }
    },
    "upstream":{
        "type":"roundrobin",
        "nodes":{
            "127.0.0.1:80":1
        }
    }
}'
```

## How does APISIX configure ETCD with authentication?

Suppose you have an ETCD cluster that enables the auth. To access this cluster, you need to configure the correct username and password for Apache APISIX in `conf/config.yaml`:

```yaml
deployment:
  etcd:
    host:
      - "http://127.0.0.1:2379"
    user: etcd_user             # username for etcd
    password: etcd_password     # password for etcd
```

For other ETCD configurations, such as expiration times, retries, and so on, you can refer to the `etcd` section in the sample configuration `conf/config.yaml.example` file.

## What is the difference between SSLs, `tls.client_cert` in upstream configurations, and `ssl_trusted_certificate` in `config.yaml`?

The `ssls` is managed through the `/apisix/admin/ssls` API. It's used for managing TLS certificates. These certificates may be used during TLS handshake (between Apache APISIX and its clients). Apache APISIX uses Server Name Indication (SNI) to differentiate between certificates of different domains.

The `tls.client_cert`, `tls.client_key`, and `tls.client_cert_id` in upstream are used for mTLS communication with the upstream.

The `ssl_trusted_certificate` in `config.yaml` configures a trusted CA certificate. It is used for verifying some certificates signed by private authorities within APISIX, to avoid APISIX rejects the certificate. Note that it is not used to trust the certificates of APISIX upstream, because APISIX does not verify the legality of the upstream certificates. Therefore, even if the upstream uses an invalid TLS certificate, it can still be accessed without configuring a root certificate.

## Where can I find more answers?

You can find more answers on:

- [Apache APISIX Slack Channel](/docs/general/join/#join-the-slack-channel)
- [Ask questions on APISIX mailing list](/docs/general/join/#subscribe-to-the-mailing-list)
- [GitHub Issues](https://github.com/apache/apisix/issues?q=is%3Aissue+is%3Aopen+sort%3Aupdated-desc) and [GitHub Discussions](https://github.com/apache/apisix/discussions)
