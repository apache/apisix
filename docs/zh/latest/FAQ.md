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

## 为什么我们需要一个新的 API 网关？不是已经有其他的开源网关了吗？

随着企业向云本地微服务的发展，对高性能、灵活、安全、可扩展的API网关的需求越来越大，一些之前的网关已经逐渐无法满足当今企业的需求。

对于上面所述的这些特点来说，APISIX相对于其它网关要做的更好，同时APISIX还具有平台无关性和完全动态交付特性，比如支持多协议、细粒度路由和多语言支持。

## APISIX 和其他的 API 网关有什么不同之处？

Apache APISIX的不同之处在于:

— 它使用etcd来保存和同步配置，而不是使用如PostgreSQL或MySQL这类的关系数据库。etcd中的实时事件通知系统比这些替代方案更容易扩展。这允许APISIX实时同步配置，使代码简洁，并避免单点故障。
- 完全动态
- 支持[热加载插件](/docs/apisix/plugins/#hot-reload)。

## APISIX 所展现出的性能如何？

与其它API网关相比较，Apache APISIX提供了最好的性能，其单核QPS高达18,000，平均延迟仅为0.2 ms。

性能基准测试的具体结果可以在[这里](benchmark.md)找到。

## Apache APISIX支持哪些平台?

Apache APISIX是和平台无关的，它是在云本地环境构建的，避免了厂商锁定。它可以在Kubernetes的裸机上运行。它甚至支持苹果硅芯片。

## 如何理解"Apache APISIX是全动态"的这句话？

Apache APISIX是完全动态的，这就意味着它不需要重新启动来改变它的行为。

它可以动态处理以下事情:

- 重新加载插件
- 代理重写
- 对请求进⾏镜像复制
- 对请求进⾏修改
- 健康状态的检查
- 动态控制指向不同上游服务的流量⽐

## APISIX 是否有控制台界面？

是的，APISIX 具有功能强大的 Dashboard。APISIX 与 [APISIX Dashboard](https://github.com/apache/apisix-dashboard) 是从Apache独立出来的一个项目，你可以通过 [APISIX Dashboard](https://github.com/apache/apisix-dashboard) 这个用户操作界面来部署Apache APISIX Dashboard。

## 我可以自己为 Apache APISIX写插件吗？

当然可以，APISIX 提供了灵活的自定义插件，方便开发者和企业编写自己的逻辑。

你可以通过这个文档来编写你自己的插件:具体可参考：[如何开发插件](plugin-develop.md)

## 为什么 Apache APISIX 选择 etcd 作为配置中心？

对于配置中心，配置存储只是最基本功能，APISIX 还需要下面几个特性：

1. 集群中的分布式部署。
2. 通过比较来监视业务。
3. 多版本并发控制。
4. 通知和观看流。
5. 高性能和最小的读/写延迟。

etcd提供了这些特性，并且使它比PostgreSQL和MySQL等其他数据库更理想。

要了解更多关于etcd与其他替代方案的比较，请参阅[对比图表](https://etcd.io/docs/latest/learning/why/#comparison-chart)。

## 使用LuaRocks安装Apache APISIX依赖项时，为什么会导致超时或安装缓慢或不成功?

这可能是因为使用的LuaRocks服务器被阻塞了。

为了解决这个问题，你可以使用https_proxy或者使用'--server '标志来指定一个更快的LuaRocks服务器。

你可以运行下面的命令来查看可用的服务器(需要LuaRocks 3.0+):

```shell
luarocks config rocks_servers
```

中国大陆用户可以使用“LuaRocks .cn”作为LuaRocks的服务器。你可以在Makefile中使用这个包装器来设置:

```bash
make deps ENV_LUAROCKS_SERVER=https://luarocks.cn
```

如果这不能解决问题，您可以尝试使用'——verbose '标志来诊断问题，从而获得详细的日志。

## 我该如何使用 Apache APISIX 发布灰色版本?

让我们举个例子,比如，`foo.com/product/index.html?id=204&page=2`, 考虑到你需要基于查询字符串中的' id '做出一个灰色发布:

1. Group A: `id <= 1000`
2. Group B: `id > 1000`

在 Apache APISIX 中有两种不同的方式来实现这一点:

1. 在`vars`文件使用[路由](architecture-design/route.md):

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

更多的 lua-resty-radixtree 匹配操作，可查看操作列表：[这里](https://github.com/api7/lua-resty-radixtree#operator-list)。

2、通过[traffic-split](plugins/traffic-split.md) 插件来实现

## 如何使用 Apache APISIX 实现从http 自动跳转到 https？

比如，将 `http://foo.com` 重定向到 `https://foo.com`

Apache APISIX 提供了几种不同的方法来实现：

1. 在[redirect](plugins/redirect.md)插件中将http_to_https设置为true:

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

3. 使用 `serverless` 插件：

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

响应信息应该是：

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

## 我应该如何更改 Apache APISIX 的日志等级?

默认的 Apache APISIX 日志等级为 `warn`，你需要将日志等级调整为 `info`来查看 `core.log.info` 的打印结果。

你可以通过修改 conf/config.yaml 中的 `nginx_config` 配置参数 `error_log_level: "warn"` 为 `error_log_level: "info"`。然后重新加载Apache APISIX。

```yaml
nginx_config:
  error_log_level: "info"
```

## 我应该如何重新加载 Apache APISIX 的自定义插件?

所有的 Apache APISIX 的插件都支持热加载的方式。

你可以通过下面的文档来了解更多关于热加载的内容，具体参考 [插件](./plugins.md) 中关于“热加载”的部分。

## 在处理HTTP或HTTPS请求时，我如何配置Apache APISIX监听多个端口?

默认情况下，APISIX 在处理 HTTP 请求时只监听 9080 端口。

要配置Apache APISIX监听多个端口，你可以:

1. 修改 `conf/config.yaml` 中 HTTP 端口监听的参数 `node_listen`，示例：

   ```
   apisix:
     node_listen:
       - 9080
       - 9081
       - 9082
   ```

   处理 HTTPS 请求也类似，修改 `conf/config.yaml` 中 HTTPS 端口监听的参数 `ssl.listen_port`，示例：

   ```
   apisix:
     ssl:
       listen_port:
         - 9443
         - 9444
         - 9445
   ```

2.重启抑或 reload APISIX。

## APISIX 利用 etcd 如何实现毫秒级别的配置同步

Apache APISIX使用etcd作为它的配置中心。Etcd提供以下订阅功能（比如： [watch](https://github.com/api7/lua-resty-etcd/blob/master/api_v3.md#watch)、[watchdir](https://github.com/api7/lua-resty-etcd/blob/master/api_v3.md#watchdir)）。它可以监视对特定关键字或目录的更改。

APISIX 主要使用 [etcd.watchdir](https://github.com/api7/lua-resty-etcd/blob/master/api_v3.md#watchdir) 监视目录内容变更：

如果监听目录没有数据更新：该调用会被阻塞，直到超时或其他错误返回。

如果监听目录有数据更新：etcd 将立刻返回订阅（毫秒级）到的新数据，APISIX 将它更新到内存缓存。

## 我应该如何自定义 APISIX 实例 id

默认情况下，APISIX 从 `conf/apisix.uid` 中读取实例 id。如果找不到，且没有配置 id，APISIX 会生成一个 `uuid` 作为实例 id。

要指定一个有意义的id来绑定Apache APISIX到您的内部系统，请在您的“conf/config”中设置“id”。yaml的文件:

```yaml
apisix:
  id: "your-id"
```

## 为什么 `error.log` 中会出现 "failed to fetch data from etcd, failed to read etcd dir, etcd key: xxxxxx" 的错误？

请按照以下步骤进行故障排除:

1. 确保Apache APISIX和集群中的etcd部署之间没有任何网络问题。
2. 如果网络正常，请检查是否为etcd启用了[gRPC gateway](https://etcd.io/docs/v3.4.0/dev-guide/api_grpc_gateway/)。默认状态取决于您是使用命令行选项还是配置文件来启动etcd服务器。

— 如果使用命令行选项，默认启用gRPC网关。可以手动启用，如下所示:

```sh
etcd --enable-grpc-gateway --data-dir=/path/to/data
```

**注意**:当运行' etcd——help '时，这个标志不会显示。

— 如果使用配置文件，默认关闭gRPC网关。您可以手动启用，如下所示:

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

**注意**:事实上这种差别已经在 etcd 的 master 分支中消除，但并没有向后移植到已经发布的版本中，所以在部署 etcd 集群时，依然需要小心。

## 我应该如何创建高可用的 Apache APISIX 集群？

Apache APISIX可以通过在其前面添加一个负载均衡器来实现高可用性，因为APISIX的数据平面是无状态的，并且可以在需要时进行扩展。

Apache APISIX 的控制平面是依赖于 `etcd cluster` 的高可用实现的，它只依赖于etcd集群。

## 安装Apache APISIX时，为什么make deps命令失败?

当执行' make deps '从源代码安装Apache APISIX时，你可能会出现如下错误:

```shell
$ make deps
......
Error: Failed installing dependency: https://luarocks.org/luasec-0.9-1.src.rock - Could not find header file for OPENSSL
  No file openssl/ssl.h in /usr/local/include
You may have to install OPENSSL in your system and/or pass OPENSSL_DIR or OPENSSL_INCDIR to the luarocks command.
Example: luarocks install luasec OPENSSL_DIR=/usr/local
make: *** [deps] Error 1
```

这是由于缺少OpenResty openssl开发工具包。要安装它，请参考[installation dependencies](install-dependencies.md)。

## 我应该如何通过 APISIX 代理访问 APISIX Dashboard

您可以按照以下步骤进行配置:

1. 为Apache APISIX代理和管理API配置不同的端口。或者，禁用管理API。

```yaml
apisix:
  port_admin: 9180 # use a separate port
```

2、添加 APISIX Dashboard 的代理路由：

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

**注意**:Apache APISIX Dashboard 正在监听' 127.0.0.1:9000 '。

## 如何在一个路由使用正则表达式(regex)匹配' uri '?

你可以通过使用 route 的 `vars` 字段来实现 uri 的正则匹配。

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

`vars` 的更多使用细节请参考 [lua-resty-expr](https://github.com/api7/lua-resty-expr)。

## upstream 节点是否支持配置 [FQDN](https://en.wikipedia.org/wiki/Fully_qualified_domain_name) 地址？

是的。下面的例子展示了如何配置一个 `FQDN` 为 `httpbin.default.svc.cluster.local`（一个 Kubernetes Service）的示例：

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

测试路由

```shell
$ curl http://127.0.0.1:9080/ip -i
HTTP/1.1 200 OK
...
```

## Admin API 的 `X-API-KEY` 指的是什么？是否可以修改？

Admin API 的 `X-API-KEY` 指的是 `config.yaml` 文件中的 `apisix.admin_key.key`，默认值是 `edd1c9f034335f136f87ad84b625c8f1`。它是 Admin API 的访问 token。

默认情况下，它被设置为“edd1c9f034335f136f87ad84b625c8f1”，并且可以通过修改您的“conf/config”中的参数来修改。yaml的文件:

```yaml
apisix:
  admin_key
    -
      name: "admin"
      key: newkey
      role: admin
```

然后访问 Admin API：

```shell
$ curl -i http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: newkey' -X PUT -d '
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

**注意**:通过使用默认令牌，您可能会暴露于安全风险。在将其部署到生产环境时，需要对其进行更新。

## 如何允许所有ip访问 Apache APISIX 的管理API?

Apache APISIX 默认只允许 `127.0.0.0/24` 的 IP 段范围访问 `Admin API`，

如果你想允许所有的 IP 访问，那么你只需在 `conf/config.yaml` 配置文件中添加如下的配置然后重新开启或重新加载 APISIX，所有 IP 便可以访问 `Admin API`。

```yaml
apisix:
  allow_admin:
    - 0.0.0.0/0
```

**注意：您可以在非生产环境中使用此方法，以允许所有客户端从任何地方访问您的 `Apache APISIX` 实例，但是在生产环境中使用它并不安全。在生产环境中，请仅授权特定的 IP 地址或地址范围访问您的实例。**

## 我应该如何基于 acme.sh 自动更新 apisix ssl 证书?

你可以运行以下命令来实现这一点:

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

详细步骤，可以参考博客 [this post](https://juejin.cn/post/6965778290619449351)。

## 在Apache APISIX中，我如何在转发到上游之前从路径中删除一个前缀?

在转发至上游之前剪除请求路径中的前缀，比如说从 `/foo/get` 改成 `/get`，你可以使用下面这个插件来实现[proxy-rewrite](plugins/proxy-rewrite.md) Plugin:

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

测试这个配置:

```shell
$ curl http://127.0.0.1:9080/foo/get -i
HTTP/1.1 200 OK
...
{
  ...
  "url": "http://127.0.0.1/get"
}
```

## 我应该如何解决 `unable to get local issuer certificate` 这个错误?

您可以手动设置证书的路径，将其添加到您的conf/config。Yaml '文件下,具体操作如下所示:

```yaml
apisix:
  ssl:
    ssl_trusted_certificate: /path/to/certs/ca-certificates.crt
```

**注意：**当你尝试使用 cosocket 连接任何 TLS 服务时，如果 APISIX 不信任对端 TLS 服务证书，都需要配置 `apisix.ssl.ssl_trusted_certificate`。

例如：在 APISIX 中使用 Nacos 作为服务发现时，Nacos 开启了 TLS 协议， 即 Nacos 配置的 `host` 是 `https://` 开头，需要配置 `apisix.ssl.ssl_trusted_certificate`，并且使用和 Nacos 相同的 CA 证书。

## 我应该如何解决 `module 'resty.worker.events' not found` 这个错误?

引起这个错误的原因是在`/root` 目录下安装了 APISIX。因为 worker 进程的用户是 nobody，无权访问 `/root` 目录下的文件。

解决办法是改变 APISIX 的安装目录，推荐安装在 `/usr/local` 目录下。

## 在Apache APISIX中，“plugin-metadata”和“plugin-configs”有什么区别?

两者之间的差异如下:

| `plugin-metadata`                                                                                                | `plugin-config`                                                                                                                                     |
| ---------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| 由插件的所有配置实例共享的插件元数据。                                        | 多个不同插件的配置实例集合。                                         |
| 当需要跨Plugin的所有配置实例传播属性更改时使用。 | 当你需要重用一组公共的配置实例，以便它可以被提取到一个“plugin-config”并绑定到不同的路由时使用。 |
| 对绑定到Plugin的配置实例的所有实体生效。                           | 对绑定到' plugin-config '的路由生效。                                                                                               |

## 我在哪里可以找到更多的答案?

- [Apache APISIX Slack Channel](/docs/general/community#joining-the-slack-channel)
- [Ask questions on APISIX mailing list](/docs/general/community#joining-the-mailing-list)
- [GitHub Issues](https://github.com/apache/apisix/issues?q=is%3Aissue+is%3Aopen+sort%3Aupdated-desc) and [GitHub Discussions](https://github.com/apache/apisix/discussions)