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

# FAQ

##  Why a new API gateway?

There are new requirements for API gateways in the field of microservices: higher flexibility, higher performance requirements, and cloud native.

##  What are the differences between APISIX and other API gateways?

APISIX is based on etcd to save and synchronize configuration, not relational databases such as Postgres or MySQL.

This not only eliminates polling, makes the code more concise, but also makes configuration synchronization more real-time. At the same time, there will be no single point in the system, which is more usable.

In addition, APISIX has dynamic routing and hot loading of plug-ins, which is especially suitable for API management under micro-service system.

## What's the performance of APISIX?

One of the goals of APISIX design and development is the highest performance in the industry. Specific test data can be found here：[benchmark](https://github.com/apache/apisix/blob/master/doc/benchmark.md)

APISIX is the highest performance API gateway with a single-core QPS of 23,000, with an average delay of only 0.6 milliseconds.

## Does APISIX have a console interface?

Yes, in version 0.6 we have dashboard built in, you can operate APISIX through the web interface.

## Can I write my own plugin?

Of course, APISIX provides flexible custom plugins for developers and businesses to write their own logic.

[How to write plugin](doc/plugin-develop.md)

## Why we choose etcd as the configuration center?

For the configuration center, configuration storage is only the most basic function, and APISIX also needs the following features:

1. Cluster
2. Transactions
3. Multi-version Concurrency Control
4. Change Notification
5. High Performance

See more [etcd why](https://github.com/etcd-io/etcd/blob/master/Documentation/learning/why.md#comparison-chart).

## Why is it that installing APISIX dependencies with Luarocks causes timeout, slow or unsuccessful installation?

There are two possibilities when encountering slow luarocks:

1. Server used for luarocks installation is blocked
2. There is a place between your network and github server to block the 'git' protocol

For the first problem, you can use https_proxy or use the `--server` option to specify a luarocks server that you can access or access faster.
Run the `luarocks config rocks_servers` command(this command is supported after luarocks 3.0) to see which server are available.

If using a proxy doesn't solve this problem, you can add `--verbose` option during installation to see exactly how slow it is. Excluding the first case, only the second that the `git` protocol is blocked. Then we can run `git config --global url."https://".insteadOf git://` to using the 'HTTPS' protocol instead of `git`.

## How to support gray release via APISIX?

An example, `foo.com/product/index.html?id=204&page=2`, gray release based on `id` in the query string in URL as a condition：

1. Group A：id <= 1000
2. Group B：id > 1000

here is the way:
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

## How to redirect http to https via APISIX?

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


## How to fix OpenResty Installation Failure on MacOS 10.15
When you install the OpenResty on MacOs 10.15, you may face this error

```shell
> brew install openresty
Updating Homebrew...
==> Auto-updated Homebrew!
Updated 1 tap (homebrew/cask).
No changes to formulae.

==> Installing openresty from openresty/brew
Warning: A newer Command Line Tools release is available.
Update them from Software Update in System Preferences or
https://developer.apple.com/download/more/.

==> Downloading https://openresty.org/download/openresty-1.15.8.2.tar.gz
Already downloaded: /Users/wusheng/Library/Caches/Homebrew/downloads/4395089f0fd423261d4f1124b7beb0f69e1121e59d399e89eaa6e25b641333bc--openresty-1.15.8.2.tar.gz
==> ./configure -j8 --prefix=/usr/local/Cellar/openresty/1.15.8.2 --pid-path=/usr/local/var/run/openresty.pid --lock-path=/usr/
Last 15 lines from /Users/wusheng/Library/Logs/Homebrew/openresty/01.configure:
DYNASM    host/buildvm_arch.h
HOSTCC    host/buildvm.o
HOSTLINK  host/buildvm
BUILDVM   lj_vm.S
BUILDVM   lj_ffdef.h
BUILDVM   lj_bcdef.h
BUILDVM   lj_folddef.h
BUILDVM   lj_recdef.h
BUILDVM   lj_libdef.h
BUILDVM   jit/vmdef.lua
make[1]: *** [lj_folddef.h] Segmentation fault: 11
make[1]: *** Deleting file `lj_folddef.h'
make[1]: *** Waiting for unfinished jobs....
make: *** [default] Error 2
ERROR: failed to run command: gmake -j8 TARGET_STRIP=@: CCDEBUG=-g XCFLAGS='-msse4.2 -DLUAJIT_NUMMODE=2 -DLUAJIT_ENABLE_LUA52COMPAT' CC=cc PREFIX=/usr/local/Cellar/openresty/1.15.8.2/luajit

If reporting this issue please do so at (not Homebrew/brew or Homebrew/core):
  https://github.com/openresty/homebrew-brew/issues

These open issues may also help:
Can't install openresty on macOS 10.15 https://github.com/openresty/homebrew-brew/issues/10
The openresty-debug package should use openresty-openssl-debug instead https://github.com/openresty/homebrew-brew/issues/3
Fails to install OpenResty https://github.com/openresty/homebrew-brew/issues/5

Error: A newer Command Line Tools release is available.
Update them from Software Update in System Preferences or
https://developer.apple.com/download/more/.
```

This is an OS incompatible issue, you could fix by these two steps
1. `brew edit openresty/brew/openresty`
1. add `\ -fno-stack-check` in with-luajit-xcflags line.

## How to change the log level?

The default log level for APISIX is `warn`. However You can change the log level to `info` if you want to trace the messages print by `core.log.info`.

Steps:

1. Modify the parameter `error_log_level: "warn"` to `error_log_level: "info"` in conf/config.yaml

2. Reload or restart APISIX

Now you can trace the info level log in logs/error.log.

## How to reload your own plugin

The Apache APISIX plugin supports hot reloading. If your APISIX node has the Admin API turned on, then for scenarios such as adding / deleting / modifying plugins, you can hot reload the plugin by calling the HTTP interface without restarting the service.

```shell
curl http://127.0.0.1:9080/apisix/admin/plugins/reload -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT
```

If your APISIX node does not open the Admin API, then you can manually load the plug-in by reloading APISIX.

```shell
apisix reload
```

## How to make APISIX listen on multiple ports when handling HTTP or HTTPS requests?

By default, APISIX only listens on port 9080 when handling HTTP requests. If you want APISIX to listen on multiple ports, you need to modify the relevant parameters in the configuration file as follows:

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

2. Reload or restart APISIX
