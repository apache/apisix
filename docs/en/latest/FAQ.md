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

## How to fix `unable to get local issuer certificate` error

`conf/config.yaml`

```yaml
# ...
apisix:
  ssl:
    ssl_trusted_certificate: /path/to/certs/ca-certificates.crt
# ...
```

**Note:**

- Whenever trying to connect TLS services with cosocket, you should set `apisix.ssl.ssl_trusted_certificate`

An example, if using Nacos as a service discovery in APISIX, Nacos has TLS protocol enabled, i.e. Nacos configuration `host` starts with `https://`, so you need to configure `apisix.ssl.ssl_trusted_certificate` and use the same CA certificate as Nacos.

## Proxy static files with APISIX, how to configure routes

Proxy static files with Nginx, for example:

```nginx
location ~* .(js|css|flash|media|jpg|png|gif|ico|vbs|json|txt)$ {
...
}
```

In `nginx.conf`, this means matching requests with js, css, etc. as a suffix. This configuration can be converted into a route with regular matching for APISIX, for example:

```json
{
    "uri": "/*",
    "vars": [
        ["uri", "~~", ".(js|css|flash|media|jpg|png|gif|ico|vbs|json|txt)$"]
    ]
}
```

## How to fix `module 'resty.worker.events' not found` error

Installing APISIX under the `/root` directory causes this problem. Because the worker process is run by nobody, it does not have access to the files in the `/root` directory. You need to move the APISIX installation directory, and it is recommended to install it in the `/usr/local` directory.

## How to get the real Client IP in APISIX

This feature relies on the [Real IP](http://nginx.org/en/docs/http/ngx_http_realip_module.html) module of Nginx, which is covered in the [APISIX-OpenResty](https://raw.githubusercontent.com/api7/apisix-build-tools/master/build-apisix-openresty.sh) script.

There are 3 directives in the Real IP module

- set_real_ip_from
- real_ip_header
- real_ip_recursive

The following describes how to use these three directives in the specific scenario.

1. Client -> APISIX -> Upstream

When the Client connects directly to APISIX, no special configuration is needed, APISIX can automatically get the real Client IP.

2. Client -> Nginx -> APISIX -> Upstream

When using Nginx as a reverse proxy between APISIX and a Client, if you do not configure APISIX for Real IP, the Client IP that APISIX gets is the IP of Nginx, not the real Client IP.

To fix this problem, Nginx needs to pass the Client IP, for example:

```nginx
location / {
    proxy_set_header X-Real-IP $remote_addr;
    proxy_pass   http://$APISIX_IP:port;
}
```

The `proxy_set_header` directive sets the `$remote_addr` variable in the `X-Real-IP` header of the current request (the `$remote_addr` variable gets the real Client IP) and passes it to APISIX. The `$APISIX_IP` means the APISIX IP in real environment.

Configure in `config.yaml` of APISIX, for example:

```yaml
nginx_config:
  http:
    real_ip_from:
      - $Nginx_IP
```

`$Nginx_IP` is the IP of Nginx in the real environment. This configuration transformed by APISIX to `nginx.conf` as

```nginx
location /get {
    real_ip_header X-Real-IP;
    real_ip_recursive off;
    set_real_ip_from $Nginx_IP;
}
```

`real_ip_from` corresponds to `set_real_ip_from` in the Real IP module, `real_ip_recursive` and `real_ip_header` directives have default values in `config-default.yaml`.

`real_ip_header X-Real-IP;` means that the Client IP is in the `X-Real-IP` header, which matches the `proxy_set_header X-Real-IP $remote_addr;` in the Nginx configuration.

`set_real_ip_from` means that `$Nginx_IP` is the IP of the trusted server. APISIX excludes `$Nginx_IP` from the search for the real Client IP. Because for APISIX, this IP is a known trusted server IP and cannot be a Client IP. set_real_ip_from` can be configured in CIDR format, such as 0.0.0.0/24.

3. Client -> Nginx1 -> Nginx2 -> APISIX -> Upstream

When using multiple Nginx as a reverse proxy between APISIX and Client, configuration of Nginx1, for example:

```nginx
location /get {
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_pass   http://$Nginx2_IP:port;
}
```

configuration of Nginx2, for example:

```nginx
location /get {
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_pass   http://$APISIX_IP:port;
}
```

The configuration uses `X-Forwarded-For`, which is used to get the real proxy path. When `X-Forwarded-For` is enabled for a proxy service, the IP of the current proxy service will be appended to the end of the `X-Forwarded-For` of each request. The format is client, proxy1, proxy2, separated by commas.

So after the Nginx1 and Nginx2 proxies, APISIX gets "X-Forwarded-For" as a proxy path like "Client IP, $Nginx1_IP, $Nginx2_IP".

Configure in `config.yaml` of APISIX, for example:

```yaml
nginx_config:
  http:
    real_ip_from:
      - $Nginx1_IP
      - $Nginx2_IP
    real_ip_header: "X-Forwarded-For"
    real_ip_recursive: "on"
```

The configuration of `real_ip_from` means that both `$Nginx1_IP` and `$Nginx2_IP` are IPs of trusted servers. How many proxy services there are between Client and APISIX, and the IPs of these proxy services need to be set in `real_ip_from`. This ensures that APISIX does not mistake IPs that appear in the search scope for Client IPs.

`real_ip_header` uses `X-Forwarded-For` and does not use the default value of `config-default.yaml`.

When `real_ip_recursive` is on, APISIX will search the value of `X-Forwarded-For` from right to left, exclude the IPs of the trusted servers, and use the first searched IP as the real Client IP.

When the request arrives at APISIX, the value of `X-Forwarded-For` is `Client IP, $Nginx1_IP, $Nginx2_IP`. Since both `$Nginx1_IP` and `$Nginx2_IP` are IPs of trusted servers, APISIX will continue to look to the left and find that `Client IP` is not the IP of any trusted servers, and determine that it is the real Client IP.

Finally, in other more complex scenarios, such as having a CDN, LB, etc. between APISIX and Client, it is necessary to understand how the Real IP module works and configure it accordingly in APISIX.

## Does APISIX support the use of etcd as a service registration and discovery center

APISIX supports service discovery using etcd. There is no service discovery API in the official implementation of etcd, so the only way to let APISIX to discover services is to implement your own framework for service registration. This is also the way used by APISIX.

When `myAPIProvider` is set into etcd via APISIX's admin api or via other ways, for example:

```shell
$ curl http://127.0.0.1:9080/apisix/admin/upstreams/myAPIProvider  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -i -X PUT -d '
{
    "type":"roundrobin",
    "nodes":{
        "39.97.63.215:80": 1
    }
}'
```

This is the service registration. In the route configuration of APISIX, you can use `myAPIProvider` directly as the upstream, for example:

```shell
$ curl "http://127.0.0.1:9080/apisix/admin/routes/1" -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" -X PUT -d '
{
  "uri": "/get",
  "upstream_id": "myAPIProvider"
}'
```

## Collect metrics for different APISIX instances in the Grafana panel

APISIX supports hostname in the prometheus plugin [exposed metrics](./plugins/prometheus.md#available-metrics) supports hostname, for example:

```shell
apisix_node_info{hostname="apisix-deployment-588bc684bb-zmz2q"} 1
```

Therefore, different APISIX instances have different hostnames, which can be distinguished in the Grafana panel.

## roundrobin load policy is not accurate, node scheduling does not follow the weights

If disabled the health check, then the roundrobin load policy schedules nodes according to the weight ratio. If enabled upstream health check, APISIX will first exclude unhealthy nodes and then schedule nodes according to the roundrobin load policy. All load balancing policies follow this rule.

This is an example of a load imbalance caused by the incorrect use of upstream health checks:

Used the default passive health check configuration, and the probe endpoint `http_path` in the active health check is the wrong, causing the active health check to probe based on `http_path` and find that the HTTP status code returned by the probe endpoint is 404, and mark the status of all upstream nodes as unhealthy. APISIX would ignore the health status of the nodes and schedules the nodes according to the load policy.

If a request is proxied to the upstream node, and the upstream node returns an HTTP status code of 200, this triggered the passive health check and mark this node as healthy again, APISIX schedules all requests to this healthy node and activates the active health check again. At the same time, APISIX activated the active health check again and probes again based on the wrong `http_path`, then get 404 HTTP status code and mark this upstream node as unhealthy again. This is repeated, resulting in unbalanced node scheduling.

## How to Configure Layer 7 Probe Endpoints for APISIX Instance Survival Status

Use [node-status](./plugins/node-status.md) or [server-info](./plugins/server-info.md) plugins, both of which have plugin API that can be used as probe endpoints.

## How to open an mTLS connection on a route

This question can be extended to how to configure mTLS connections between Client and APISIX, between Control Plane and APISIX, between APISIX and Upstream, and between APISIX and etcd。

The mTLS connection on the route is the mTLS connection between the Client and APISIX.

The pre-requisites for enabling the mTLS protocol are: CA certificate, client certificate, client key, server certificate, and server key. The below example uses the certificate file from APISIX for the test case.

1. Upload certificates

APISIX provides an API to upload certificates dynamically, you can also upload certificates in APISIX-Dashboard. For visualization, I use a test case to upload ssl certificate, example.

```perl
=== TEST 1: set ssl(sni: admin.apisix.dev)
--- config
location /t {
    content_by_lua_block {
        local core = require("apisix.core")
        local t = require("lib.test_admin")

        local ssl_cert = t.read_file("t/certs/mtls_server.crt")
        local ssl_key =  t.read_file("t/certs/mtls_server.key")
        local ssl_cacert = t.read_file("t/certs/mtls_ca.crt")
        local data = {cert = ssl_cert, key = ssl_key, sni = "admin.apisix.dev", client = {ca = ssl_cacert, depth = 5}}

        local code, body = t.test('/apisix/admin/ssl/1',
            ngx.HTTP_PUT,
            core.json.encode(data),
            [[{
                "node": {
                    "value": {
                        "sni": "admin.apisix.dev"
                    },
                    "key": "/apisix/ssl/1"
                },
                "action": "set"
            }]]
            )

        ngx.status = code
        ngx.say(body)
    }
}
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]
```

Note: You need to set the CA certificate and the certificate depth for client certificate verification, i.e. `client.ca` and `client.depth`. Also note: mtls_ca.crt is signed by the SNI `admin.apisix.dev`.

2. Set Route

for example:

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -i -d '
{
    "uri": "/get",
    "hosts": ["admin.apisix.dev"],
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "httpbin.org:80": 1
        }
    }
}'
```

On the route, the hosts attribute is specified as `admin.apisix.dev`. APISIX will query the associated SNI CA certificate, server certificate and server key according to the domain name by the request. This process is equivalent to binding the route and the certificate.

3. Test

```shell
curl --cert /usr/local/apisix/t/certs/mtls_client.crt --key /usr/local/apisix/t/certs/mtls_client.key --cacert /usr/local/apisix/t/certs/mtls_ca.crt --resolve 'admin.apisix.dev:9443:127.0.0.1' https://admin.apisix.dev:9443/get -vvv

* Added admin.apisix.dev:9443:127.0.0.1 to DNS cache
* Hostname admin.apisix.dev was found in DNS cache
*   Trying 127.0.0.1:9443...
* Connected to admin.apisix.dev (127.0.0.1) port 9443 (#0)
* ALPN, offering h2
* ALPN, offering http/1.1
* successfully set certificate verify locations:
*   CAfile: /usr/local/apisix/t/certs/mtls_ca.crt
  CApath: none
* TLSv1.3 (OUT), TLS handshake, Client hello (1):
* TLSv1.3 (IN), TLS handshake, Server hello (2):
* TLSv1.3 (IN), TLS handshake, Encrypted Extensions (8):
* TLSv1.3 (IN), TLS handshake, Request CERT (13):
* TLSv1.3 (IN), TLS handshake, Certificate (11):
* TLSv1.3 (IN), TLS handshake, CERT verify (15):
* TLSv1.3 (IN), TLS handshake, Finished (20):
* TLSv1.3 (OUT), TLS change cipher, Change cipher spec (1):
* TLSv1.3 (OUT), TLS handshake, Certificate (11):
* TLSv1.3 (OUT), TLS handshake, CERT verify (15):
* TLSv1.3 (OUT), TLS handshake, Finished (20):
* SSL connection using TLSv1.3 / TLS_AES_256_GCM_SHA384
* ALPN, server accepted to use h2
* Server certificate:
*  subject: C=cn; ST=GuangDong; O=api7; L=ZhuHai; CN=admin.apisix.dev
*  start date: Jun 20 13:14:34 2020 GMT
*  expire date: Jun 18 13:14:34 2030 GMT
*  common name: admin.apisix.dev (matched)
*  issuer: C=cn; ST=GuangDong; L=ZhuHai; O=api7; OU=ops; CN=ca.apisix.dev
*  SSL certificate verify ok.
* Using HTTP2, server supports multi-use
* Connection state changed (HTTP/2 confirmed)
* Copying HTTP/2 data in stream buffer to connection buffer after upgrade: len=0
* Using Stream ID: 1 (easy handle 0xaaaad8ffadd0)
> GET /get HTTP/2
> Host: admin.apisix.dev:9443
> user-agent: curl/7.71.1
> accept: */*
>
* TLSv1.3 (IN), TLS handshake, Newsession Ticket (4):
* TLSv1.3 (IN), TLS handshake, Newsession Ticket (4):
* old SSL session ID is stale, removing
* Connection state changed (MAX_CONCURRENT_STREAMS == 128)!
< HTTP/2 200
< content-type: application/json
< content-length: 320
< date: Tue, 06 Jul 2021 15:40:14 GMT
< access-control-allow-origin: *
< access-control-allow-credentials: true
< server: APISIX/2.7
<
{
  "args": {},
  "headers": {
    "Accept": "*/*",
    "Host": "admin.apisix.dev",
    "User-Agent": "curl/7.71.1",
    "X-Amzn-Trace-Id": "Root=1-60e4795e-4dd03a271242afe233d53ef6",
    "X-Forwarded-Host": "admin.apisix.dev"
  },
  "origin": "127.0.0.1, 49.70.187.161",
  "url": "http://admin.apisix.dev/get"
}
* Connection #0 to host admin.apisix.dev left intact
```

The `curl` command specifies the CA certificate, client certificate, and client key. Since this is a local test, the `--resolve` command is used so that `admin.apisix.dev` is pointed to `127.0.0.1` and triggered the request successfully.

From the TLS handshake process, we can see that a certificate verification is performed between Client and APISIX to complete the process of mTLS protocol processing. From the response, we can see that APISIX has completed the request proxy forwarding.

How to configure the mTLS connection between Control Plane and APISIX, between APISIX and Upstream, and between APISIX and etcd, respectively, can be found in [mtls](./mtls.md).

## APISIX accept TLS over TCP

Refer to [Accept TLS over TCP](./stream-proxy.md#accept-tls-over-tcp), it should be noted that on the TCP protocol, at present, APISIX only supports to uninstall tls certificate as server and does not support to access the upstream with tls enabled as client.

## What is the relationship between passive health checks and retry

If the retry fails, APISIX will report the retry node failure information to the passive health check.

## What is the difference between `plugin_metadata` and `plugin-configs`

`plugin_metadata` is the metadata of the plugin, which is shared by all plugin instances. When writing a plugin, if there are some plugin properties that are shared by all plugin instances and the changes take effect for all plugin instances, then it is appropriate to put them in `plugin_metadata`.

`plugin-configigs` is a collection of multiple plugin instances. If you want to reuse a common set of plugin configurations, you can extract them into a Plugin Config and bind them to the corresponding routes.

The difference between `plugin_metadata` and `plugin-configs`:

- Plugin instance scope: `plugin_metadata` works on all instances of this plugin. `plugin-configs` works on the plugin instances configured under it.
- Binding entities: `plugin_metadata` take effect on the entities bound to all instances of this plugin. `plugin-configs` take effect on the routes bound to this `plugin-configs`.

## Configure the `limit-req` plugin on both the Route and the Consumer, with different properties for the two configurations, what is the effect

Only the `limit-req` plugin on Consumer will take effect. Most plugins follow this rule.

## How to use the environment variable `INTRANET_IP` configured by the prometheus plugin

`INTRANET_IP` Usage Scenario Example: If APISIX is deployed on a server within the intranet, there are several NICs on this server, each with an IP. `INTRANET_IP` is used to select one of the IPs to be exposed. This way, only other services in the same network segment within the intranet can access it, and no services not in the same intranet segment can access it.

## How to use the plugin hot reload

This feature has been improved on APISIX v2.7 to update the code of the plugin in real time. The steps are as below:

1. Configuring the plugin on the route and the plugin taking effect;
2. Modification of the source code of the running plugin;
3. Use [`/apisix/admin/plugins/reload`](./architecture-design/plugin.md#hot-reload) API to update the plugin;

**Note: This operation will take effect in real time. If it is a production environment, make sure that the modified plugin code is correct.**

## What is the relationship between `config.yaml` and `config-default.yaml`

`config-default.yaml` is the default configuration file for APISIX. Users can refer to the configuration items in `config-default.yaml` and make custom changes in `config.yaml`. The configuration items in `config.yaml` will override the configuration items of the same name in `config-default.yaml`.

Note: Configuring `plugins` in `config.yaml` will override all `plugins` in `config-default.yaml`, which can disable some plugins.

## How to fix the log with HTTP status code 499 was found in `error.log`

Nginx defines 499 HTTP status codes that means client closes the connection without waiting for a response, controlled by the [`proxy_ignore_client_abort`](http://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_ignore_client_abort) command.

In APISIX, you can turn on `proxy_ignore_client_abort` via [customize Nginx configuration](./customize-nginx-configuration.md), which means that APISIX ignores client abort exceptions, does not break the connection to the upstream earlier, and always waits for the upstream response.

for example:

```yaml
nginx_config:
  http_server_configuration_snippet: |
    proxy_ignore_client_abort on;
```

## How to fix the log with `upstream response is buffered to a temporary file` was found in `error.log`

This is because the Nginx upstream module has a non-zero temporary file size configuration by default, controlled by the [`proxy_max_temp_file_size`](http://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_max_temp_file_size) directive. When the memory buf runs out in a request, and then saved the data to a file.

In APISIX, you can adjust the size of the `proxy_max_temp_file_size` via [customize Nginx configuration](./customize-nginx-configuration.md), for example:

```yaml
nginx_config:
  http_server_configuration_snippet: |
    proxy_max_temp_file_size 2G;
```

## Why does the `body_filter` phase execute many times

Nginx `output filter` may be called many times during a request, as the response body may be passed in chunks. Therefore, the Lua code in `body_filter` may also be run many times during the lifetime of an HTTP request. See [body_filter_by_lua](https://github.com/openresty/lua-nginx-module#body_filter_by_lua) for more information.

You can refer to the code of the [grpc-transcode](https://github.com/apache/apisix/blob/master/apisix/plugins/grpc-transcode/response.lua) plugin for more information on how to get the full content of the response body.
