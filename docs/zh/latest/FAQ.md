---
title: 常见问题
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

## 为什么要做 API 网关？不是已经有其他的开源网关了吗？

微服务领域对 API 网关有新的需求：更高的灵活性、更高的性能要求，以及云原生的贴合。

## APISIX 和其他的 API 网关有什么不同之处？

APISIX 基于 etcd 来完成配置的保存和同步，而不是 postgres 或者 MySQL 这类关系型数据库。
这样不仅去掉了轮询，让代码更加的简洁，配置同步也更加实时。同时系统也不会存在单点，可用性更高。

另外，APISIX 具备动态路由和插件热加载，特别适合微服务体系下的 API 管理。

## APISIX 的性能怎么样？

APISIX 设计和开发的目标之一，就是业界最高的性能。具体测试数据见这里：[benchmark](benchmark.md)

APISIX 是当前性能最好的 API 网关，单核 QPS 达到 2.3 万，平均延时仅有 0.6 毫秒。

## APISIX 是否有控制台界面？

是的，APISIX 具有功能强大的 Dashboard。APISIX 与 [APISIX Dashboard](https://github.com/apache/apisix-dashboard) 是相互独立的项目，你可以部署 [APISIX Dashboard](https://github.com/apache/apisix-dashboard) 通过 web 界面来操作 APISIX。

## 我可以自己写插件吗？

当然可以，APISIX 提供了灵活的自定义插件，方便开发者和企业编写自己的逻辑。

[如何开发插件](plugin-develop.md)

## 我们为什么选择 etcd 作为配置中心？

对于配置中心，配置存储只是最基本功能，APISIX 还需要下面几个特性：

1. 集群支持
2. 事务
3. 历史版本管理
4. 变化通知
5. 高性能

APISIX 需要一个配置中心，上面提到的很多功能是传统关系型数据库和 KV 数据库是无法提供的。与 etcd 同类软件还有 Consul、ZooKeeper 等，更详细比较可以参考这里：[etcd why](https://github.com/etcd-io/website/blob/master/content/en/docs/next/learning/why.md#comparison-chart)，在将来也许会支持其他配置存储方案。

## 为什么在用 Luarocks 安装 APISIX 依赖时会遇到超时，很慢或者不成功的情况？

遇到 luarocks 慢的问题，有以下两种可能：

1. luarocks 安装所使用的服务器不能访问
2. 你所在的网络到 github 服务器之间有地方对 `git` 协议进行封锁

针对第一个问题，你可以使用 https_proxy 或者使用 `--server` 选项来指定一个你可以访问或者访问更快的
luarocks 服务。 运行 `luarocks config rocks_servers` 命令（这个命令在 luarocks 3.0 版本后开始支持）
可以查看有哪些可用服务。对于中国大陆用户，你可以使用 `luarocks.cn` 这一个 luarocks 服务。

我们已经封装好了选择服务地址的操作：

```bash
LUAROCKS_SERVER=https://luarocks.cn make deps
```

如果使用代理仍然解决不了这个问题，那可以在安装的过程中添加 `--verbose` 选项来查看具体是慢在什么地方。排除前面的
第一种情况，只可能是第二种，`git` 协议被封。这个时候可以执行 `git config --global url."https://".insteadOf git://` 命令使用 `https` 协议替代。

## 如何通过 APISIX 支持灰度发布？

比如，`foo.com/product/index.html?id=204&page=2`, 根据 URL 中 query string 中的 `id` 作为条件来灰度发布：

1. A 组：id <= 1000
2. B 组：id > 1000

有两种不同的方法来实现：

1、使用 route 的 `vars` 字段来实现

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

更多的 lua-resty-radixtree 匹配操作，可查看操作列表：
https://github.com/api7/lua-resty-radixtree#operator-list

2、通过 traffic-split 插件来实现

详细使用示例请参考 [traffic-split.md](plugins/traffic-split.md) 插件文档。

## 如何支持 http 自动跳转到 https？

比如，将 `http://foo.com` 重定向到 `https://foo.com`

有几种不同的方法来实现：

1. 直接使用 `redirect` 插件的 `http_to_https` 功能：

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

2. 结合高级路由规则 `vars` 和 `redirect` 插件一起使用：

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

3. 使用`serverless`插件：

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

然后测试下是否生效：

```shell
curl -i -H 'Host: foo.com' http://127.0.0.1:9080/hello
```

响应体应该是：

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

## 如何修改日志等级

默认的 APISIX 日志等级为`warn`，如果需要查看`core.log.info`的打印结果需要将日志等级调整为`info`。

具体步骤：

1、修改 conf/config.yaml 中的 `nginx_config` 配置参数`error_log_level: "warn"` 为 `error_log_level: "info"`。

```yaml
nginx_config:
  error_log_level: "info"
```

2、重启抑或 reload APISIX

之后便可以在 logs/error.log 中查看到 info 的日志了。

## 如何加载自己编写的插件

Apache APISIX 的插件支持热加载。

具体怎么做参考 [插件](./plugins.md) 中关于“热加载”的部分。

## 如何让 APISIX 在处理 HTTP 或 HTTPS 请求时监听多个端口

默认情况下，APISIX 在处理 HTTP 请求时只监听 9080 端口。如果你想让 APISIX 监听多个端口，你需要修改配置文件中的相关参数，具体步骤如下：

1. 修改 `conf/config.yaml` 中 HTTP 端口监听的参数`node_listen`，示例：

   ```
   apisix:
     node_listen:
       - 9080
       - 9081
       - 9082
   ```

   处理 HTTPS 请求也类似，修改`conf/config.yaml`中 HTTPS 端口监听的参数`ssl.listen_port`，示例：

   ```
   apisix:
     ssl:
       listen_port:
         - 9443
         - 9444
         - 9445
   ```

2.重启抑或 reload APISIX

## APISIX 利用 etcd 如何实现毫秒级别的配置同步

etcd 提供订阅接口用于监听指定关键字、目录是否发生变更（比如： [watch](https://github.com/api7/lua-resty-etcd/blob/master/api_v3.md#watch)、[watchdir](https://github.com/api7/lua-resty-etcd/blob/master/api_v3.md#watchdir)）。

APISIX 主要使用 [etcd.watchdir](https://github.com/api7/lua-resty-etcd/blob/master/api_v3.md#watchdir) 监视目录内容变更：

* 如果监听目录没有数据更新：该调用会被阻塞，直到超时或其他错误返回。
* 如果监听目录有数据更新：etcd 将立刻返回订阅(毫秒级)到的新数据，APISIX 将它更新到内存缓存。

借助 etcd 增量通知毫秒级特性，APISIX 也就完成了毫秒级的配置同步。

## 如何自定义 APISIX 实例 id

默认情况下，APISIX 会从 `conf/apisix.uid` 中读取实例 id。如果找不到，且没有配置 id，APISIX 会生成一个 `uuid` 作为实例 id。

如果你想指定一个有意义的 id 来绑定 APISIX 实例到你的内部系统，你可以在 `conf/config.yaml` 中进行配置，示例：

    ```
    apisix:
      id: "your-meaningful-id"
    ```

## 为什么 `error.log` 中会有许多诸如 "failed to fetch data from etcd, failed to read etcd dir, etcd key: xxxxxx" 的错误？

首先请确保 APISIX 和 etcd 之间不存在网络分区的情况。

如果网络的确是健康的，请检查你的 etcd 集群是否启用了 [gRPC gateway](https://etcd.io/docs/v3.4.0/dev-guide/api_grpc_gateway/) 特性。然而，当你使用命令行参数或配置文件启动 etcd 时，此特性的默认启用情况又是不同的。

1. 当使用命令行参数启动 etcd，该特性默认被启用，相关选项是 `enable-grpc-gateway`。

```sh
etcd --enable-grpc-gateway --data-dir=/path/to/data
```

注意该选项并没有展示在 `etcd --help` 的输出中。

2. 使用配置文件时，该特性默认被关闭，请明确启用 `enable-grpc-gateway` 配置项。

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

事实上这种差别已经在 etcd 的 master 分支中消除，但并没有向后移植到已经发布的版本中，所以在部署 etcd 集群时，依然需要小心。

## 如何创建高可用的 Apache APISIX 集群？

APISIX 的高可用可分为两个部分：

1、Apache APISIX 的数据平面是无状态的，可以进行随意的弹性伸缩，前面加一层 LB 即可。

2、Apache APISIX 的控制平面是依赖于 `etcd cluster` 的高可用实现的，不需要任何关系型数据库的依赖。

## 为什么源码安装中执行 `make deps` 命令失败？

1、当执行 `make deps` 命令时，发生诸如下面所示的错误。这是由于缺少 OpenResty  的 `openssl` 开发软件包导致的，你需要先安装它。请参考 [install dependencies](install-dependencies.md) 文档进行安装。

```shell
$ make deps
......
Error: Failed installing dependency: https://luarocks.org/luasec-0.9-1.src.rock - Could not find header file for OPENSSL
  No file openssl/ssl.h in /usr/local/include
You may have to install OPENSSL in your system and/or pass OPENSSL_DIR or OPENSSL_INCDIR to the luarocks command.
Example: luarocks install luasec OPENSSL_DIR=/usr/local
make: *** [deps] Error 1
```

## 如何通过 APISIX 代理访问 APISIX Dashboard

1、保持 APISIX 代理端口和 Admin API 端口不同（或禁用 Admin API）。例如，在 `conf/config.yaml` 中做如下配置。

Admin API 使用独立端口 9180：

```yaml
apisix:
  port_admin: 9180            # use a separate port
```

2、添加 APISIX Dashboard 的代理路由：

注意：这里的 APISIX Dashboard 服务正在监听 `127.0.0.1:9000`。

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

## route 的 `uri` 如何进行正则匹配

这里通过 route 的 `vars` 字段来实现 uri 的正则匹配。

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

测试请求：

```shell
# uri 匹配成功
$ curl http://127.0.0.1:9080/hello -i
HTTP/1.1 200 OK
...

# uri 匹配失败
$ curl http://127.0.0.1:9080/12ab -i
HTTP/1.1 404 Not Found
...
```

在 route 中，我们可以通过 `uri` 结合 `vars` 字段来实现更多的条件匹配，`vars` 的更多使用细节请参考 [lua-resty-expr](https://github.com/api7/lua-resty-expr)。

## upstream 节点是否支持配置 [FQDN](https://en.wikipedia.org/wiki/Fully_qualified_domain_name) 地址?

这是支持的，下面是一个 `FQDN` 为 `httpbin.default.svc.cluster.local`(一个 Kubernetes Service) 的示例：

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
# 测试请求
$ curl http://127.0.0.1:9080/ip -i
HTTP/1.1 200 OK
...
```

## Admin API 的 `X-API-KEY` 指的是什么？是否可以修改？

1、Admin API 的 `X-API-KEY` 指的是 `config.yaml` 文件中的 `apisix.admin_key.key`，默认值是 `edd1c9f034335f136f87ad84b625c8f1`。它是 Admin API 的访问 token。

注意：使用默认的 API token 存在安全风险，建议在部署到生产环境时对其进行更新。

2、`X-API-KEY` 是可以修改的。

例如：在 `conf/config.yaml` 文件中对 `apisix.admin_key.key` 做如下修改并 reload APISIX。

```yaml
apisix:
  admin_key
    -
      name: "admin"
      key: abcdefghabcdefgh
      role: admin
```

访问 Admin API：

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

路由创建成功，表示 `X-API-KEY` 修改生效。

## 如何允许所有 IP 访问 Admin API

Apache APISIX 默认只允许 `127.0.0.0/24` 的 IP 段范围访问 `Admin API`，如果你想允许所有的 IP 访问，那么你只需在 `conf/config.yaml` 配置文件中添加如下的配置。

```yaml
apisix:
  allow_admin:
    - 0.0.0.0/0
```

重启或 reload APISIX，所有 IP 便可以访问 `Admin API`。

**注意：您可以在非生产环境中使用此方法，以允许所有客户端从任何地方访问您的 `Apache APISIX` 实例，但是在生产环境中使用它并不安全。在生产环境中，请仅授权特定的 IP 地址或地址范围访问您的实例。**

## 基于 acme.sh 自动更新 apisix ssl 证书

```bash
$ curl --output /root/.acme.sh/renew-hook-update-apisix.sh --silent https://gist.githubusercontent.com/anjia0532/9ebf8011322f43e3f5037bc2af3aeaa6/raw/65b359a4eed0ae990f9188c2afa22bacd8471652/renew-hook-update-apisix.sh

$ chmod +x /root/.acme.sh/renew-hook-update-apisix.sh

$ acme.sh  --issue  --staging  -d demo.domain --renew-hook "~/.acme.sh/renew-hook-update-apisix.sh  -h http://apisix-admin:port -p /root/.acme.sh/demo.domain/demo.domain.cer -k /root/.acme.sh/demo.domain/demo.domain.key -a xxxxxxxxxxxxx"

$ acme.sh --renew --domain demo.domain

```

详细步骤，可以参考博客 https://juejin.cn/post/6965778290619449351

## 如何在路径匹配时剪除请求路径前缀

在转发至上游之前剪除请求路径中的前缀，比如说从 `/foo/get` 改成 `/get`，可以通过插件 `proxy-rewrite` 实现。

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

测试请求：

```shell
$ curl http://127.0.0.1:9080/foo/get -i
HTTP/1.1 200 OK
...
{
  ...
  "url": "http://127.0.0.1/get"
}
```

## 如何解决 `unable to get local issuer certificate` 错误

修改 `conf/config.yaml`

```yaml
# ... 忽略其余无关项
apisix:
  ssl:
    ssl_trusted_certificate: /path/to/certs/ca-certificates.crt
# ... 忽略其余无关项
```

**注意:**
尝试使用 cosocket 连接任何 TLS 服务时，都需要配置 `apisix.ssl.ssl_trusted_certificate`。

## 用 APISIX 代理静态文件，如何配置路由

用 nginx 代理静态文件，常用配置示例：

```nginx
location ~* .(js|css|flash|media|jpg|png|gif|ico|vbs|json|txt)$ {
...
}
```

在 nginx.conf 中，这个配置表示匹配 url 的后缀是 js, css 等的请求。转换成 APISIX 的路由配置，需要使用 APISIX 的正则匹配，示例：

```json
{
    "uri": "/*",
    "vars": [
        ["uri", "~~", ".(js|css|flash|media|jpg|png|gif|ico|vbs|json|txt)$"]
    ]
}
```

## 如何解决 `module 'resty.worker.events' not found` 错误

把 APISIX 安装在了 `/root` 目录下会导致这个问题，即使用 root 用户启动也无法避免。因为 worker 进程属于 nobody 用户，无权访问 `/root` 目录下的文件。需要移动 APISIX 的安装目录，推荐安装在 `/usr/local` 目录下。

## 如何在 APISIX 中获取真实的客户端 IP

首这个功能依赖于 Nginx 的 [Real IP](http://nginx.org/en/docs/http/ngx_http_realip_module.html) 模块，在 [APISIX-OpenResty](https://raw.githubusercontent.com/api7/apisix-build-tools/master/build-apisix-openresty.sh) 脚本中涵盖了 Real IP 模块。

Real IP 模块中有 3 个配置
- set_real_ip_from： 定义受信任的地址，这些已知地址会发送正确的替换地址。
- real_ip_header： 定义请求头字段，其值将被用来替换客户端地址。
- real_ip_recursive： 如果禁用递归搜索，则与受信任地址之一匹配的原始客户端地址将替换为 real_ip_header 指令定义的请求标头字段中发送的最后一个地址。

下面结合具体场景介绍这三个指令如何使用。

1. Client -> APISIX -> Upstream

在 Client 直连 APISIX 场景下，不需要作特殊配置，APISIX 可以自动获取真实的 Client IP。

2. Client -> Nginx -> APISIX -> Upstream

这种场景下，APISIX 与 Client 之间有 Nginx 做反向代理。如果 APISIX 不做任何配置，那么获取到的 Client IP 是 Nginx 的 IP，而不是真实的 Client 的 IP。

为了解决这个问题，Nginx 需要传递 Client IP，配置示例：

```nginx
location / {
    proxy_set_header X-Real-IP $remote_addr;
    proxy_pass   http://$APISIX_IP:port;
}
```

其中 `$remote_addr` 变量获取的是真实的 Client IP，用 `proxy_set_header` 指令把 Client IP 设置在请求的 `X-Real-IP` header 中，并向后传递给 APISIX。 `$APISIX_IP` 是指真实环境中的 APISIX 的 IP。

APISIX 的 `config.yaml` 配置示例：

```yaml
nginx_config:
  http:
    real_ip_from:
      - $Nginx_IP
```

上面配置的 `$Nginx_IP` 是指真实环境中的 Nginx 的 IP。该配置在 APISIX 生成的 `nginx.conf` 中如下：

```nginx
location /get {
    real_ip_header X-Real-IP;
    real_ip_recursive off;
    set_real_ip_from $Nginx_IP;
}
```

其中 `real_ip_from` 对应的是 Real IP 模块设置的 `set_real_ip_from`，`config.yaml` 中虽然没有 `real_ip_recursive` 和 `real_ip_header`，但是在 `config-default.yaml` 中设置了缺省值。

`real_ip_header X-Real-IP;` 表示 Client IP 在 `X-Real-IP` 这个 header 中，与 Nginx 配置中的 `proxy_set_header X-Real-IP $remote_addr;` 契合。

`set_real_ip_from` 表示配置的 `$Nginx_IP` 是信任服务器的 IP。在寻找真实的 Client IP 的时候，在搜索范围内把 `$Nginx_IP` 剔除掉，因为对于 APISIX 来说，这个 IP 确定是可信任的服务器 IP，不可能是 Client IP。`set_real_ip_from` 可以配置成 CIDR 的格式，即网段，例如 0.0.0.0/24。


3. Client -> Nginx1 -> Nginx2 -> APISIX -> Upstream

这种场景是指 APISIX 与 Client 之间有多个 Nginx 做反向代理。

Nginx1 配置示例：

```nginx
location /get {
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_pass   http://$Nginx2_IP:port;
}
```

Nginx2 配置示例：

```nginx
location /get {
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_pass   http://$APISIX_IP:port;
}
```

配置中使用了 `X-Forwarded-For`，它的用途是获取真实的代理路径。代理服务开启了 `X-Forwarded-For` 设置后，每次经过代理转发都会在 `X-Forwarded-For` 这个 header 的末尾追加当前代理服务的 IP。格式是 client, proxy1, proxy2, 以逗号隔开。

所以经过 Nginx1 和 Nginx2 的代理，APISIX 获得的 "X-Forwarded-For" 是 "Client IP, $Nginx1_IP, $Nginx2_IP" 这样的代理路径。

APISIX 的 `config.yaml` 配置示例：

```yaml
nginx_config:
  http:
    real_ip_from:
      - $Nginx1_IP
      - $Nginx2_IP
    real_ip_header: "X-Forwarded-For"
    real_ip_recursive: "on"
```

`real_ip_from` 的配置表示 `$Nginx1_IP` 和 `$Nginx2_IP` 都是可信服务器的 IP。可以这样理解： Client 和 APISIX 之间有多少层代理服务，这些代理服务的 IP 都需要设置在 `real_ip_from` 中。确保 APISIX 不会把搜索范围内出现的 IP 误认为是 Client IP。

`real_ip_header` 使用了 `X-Forwarded-For`，不用 `config-default.yaml` 的缺省值。

当 `real_ip_recursive` 为 on 时，APISIX 会在 `X-Forwarded-For` 的值中从右往左搜索，剔除掉信任服务器的 IP，把最先搜索到的 IP 作为真实的 Client IP。

当请求到达 APISIX 时，`X-Forwarded-For` 的值是 "Client IP, $Nginx1_IP, $Nginx2_IP"。由于 `$Nginx1_IP` 和 `$Nginx2_IP` 都是可信服务器的 IP，所以 APISIX 会继续往左查询，发现 `Client IP` 不是可信服务器的 IP，就判断为真实的 Client IP。

最后，在其他更复杂的场景中，比如 APISIX 与 Client 之间有 CDN，LB 等，需要理解 Real IP 模块的工作方式，并在 APISIX 中进行相应的配置。

## APISIX 支持使用 etcd 作为服务注册与发现中心吗

APISIX 支持使用 etcd 进行服务发现，etcd 官方实现中没有服务发现 API，因此，唯一方法是自己实现服务注册的框架。这也是 APISIX 采用的方式。

当通过 APISIX 的 admin api 或通过其他方式将 `myAPIProvider` 配置放入 etcd 时，示例：

```shell
$ curl http://127.0.0.1:9080/apisix/admin/upstreams/myAPIProvider  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -i -X PUT -d '
{
    "type":"roundrobin",
    "nodes":{
        "39.97.63.215:80": 1
    }
}'
```

就是服务注册了，在 APISIX 的路由配置中，可以直接使用 `myAPIProvider` 作为上游，示例：

```shell
$ curl "http://127.0.0.1:9080/apisix/admin/routes/1" -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" -X PUT -d '
{
  "uri": "/get",
  "upstream_id": "myAPIProvider"
}'
```

## 在 Grafana 面板中收集不同 APISIX 实例的指标

APISIX 在 prometheus 插件[暴露的指标](./plugins/prometheus.md#可有的指标)中支持 hostname，例如

```shell
apisix_node_info{hostname="apisix-deployment-588bc684bb-zmz2q"} 1
```

因此，不同的 APISIX 实例设置不同的 hostname，在 Grafana 面板中即可加以区分。

## roundrobin 负载策略不准确，节点调度并没有完全按照权重来进行

如果不开启健康检查，那么 roundrobin 负载策略是按照权重比调度节点。如果开启了上游健康检查，APISIX 会先剔除掉不健康的节点，然后根据 roundrobin 负载策略调度节点。所有的负载均衡策略都遵循这个规则。

这是一则错误使用上游健康检查导致负载不均衡的例子：

使用默认的被动健康检查配置，并且主动健康检查配置中的探测端点 `http_path` 配了错误的 url，导致主动健康检查根据 `http_path` 探测，发现探测端点返回的 HTTP 状态码是 404，于是标记所有上游节点的状态为不健康。这时健康检查会降级为默认的权重模式，roundrobin 按照权重比调度节点。

如果有请求被代理到了上游节点，并且上游节点返回 HTTP 状态码是 200，触发被动健康检查将此节点又标记为健康，APISIX 会把请求都调度到这个健康的节点，同时再次激活主动健康检查，主动健康检查并根据错误的 `http_path` 再次进行探测并收到 404 HTTP 状态码，又将此上游节点标记为不健康。如此反复，导致节点调度不均衡。

## APISIX 实例存活状态的七层探测端点如何配置

使用 [node-status](./plugins/node-status.md) 或者 [server-info](./plugins/server-info.md) 插件，它们的插件接口都可以作为探测端点。

## 如何开启路由上的 mTLS 连接

这个问题可以整理归类为：Client 与 APISIX 之间，Control Plane 与 APISIX 之间，APISIX 与 Upstream 之间，APISIX 与 etcd 之间分别如何配置 mTLS 连接。

路由上的 mTLS 连接即 Client 与 APISIX 之间使用 mTLS 连接。

开启 mTLS 协议的前置准备有：CA 证书，以及由这个 CA 证书签发的客户端证书，客户端密钥，服务端证书，服务端密钥。以下示例中使用 APISIX 用于测试用例的相关证书文件。

1. 上传证书

APISIX 提供了动态上传证书的接口，你也可以在 APISIX-Dashboard 中上传证书。为了直观，我用测试用例的方式上传 ssl 证书,示例：

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

注意：要设置将用于客户端证书校验的 CA 证书以及客户端证书校验的深度，即 `client.ca` 和 `client.depth`。另外需要说明：mtls_ca.crt 这个证书签署的 SNI 是 `admin.apisix.dev`。

2. 设置路由

示例：

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

在路由上，指定了 hosts 属性是 `admin.apisix.dev`。APISIX 会根据请求携带的域名， 查询域名对应的 SNI 关联的 CA 证书，服务器证书和服务器密钥。这个过程相当于绑定路由和证书。

3. 测试

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

`curl` 命令指定了 CA 证书，客户端证书，客户端密钥，由于是本地测试，所以用 `--resolve` 指令所以把 `admin.apisix.dev` 指向 `127.0.0.1`，成功触发请求。

从 TLS 握手的过程可以看到，Client 与 APISIX 之间进行了证书校验，完成 mTLS 协议处理的过程。从响应中可以看到，APISIX 完成了请求代理转发。

Control Plane 与 APISIX 之间，APISIX 与 Upstream 之间，APISIX 与 etcd 之间分别如何配置 mTLS 连接，可以参考 [mtls](./mtls.md)。

## APISIX 代理四层协议并使用 tls 功能

参考 [接收 TLS over TCP](./stream-proxy.md#接收-tls-over-tcp)，需要说明的是，在四层协议上，目前只支持 APISIX 作为 server 去卸载 tls 证书，不支持 APISIX 作为 client 去访问开启 tls 的上游。

