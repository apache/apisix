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

## 为什么需要一个新的 API 网关？不是已经有其他的开源网关了吗？

随着企业向云本地微服务的发展，企业对高性能、灵活、安全、可扩展的 API 网关的需求越来越大。

APISIX 在这些指标表现上优于其它 API 网关，同时具有平台无关性和完全动态的特性，如支持多种协议、细粒度路由和多语言支持。

## APISIX 和其他的 API 网关有什么不同之处？

Apache APISIX 在以下方面有所不同：

— 它使用 etcd 来保存和同步配置，而不是使用如 PostgreSQL 或 MySQL 这类的关系数据库。etcd 中的实时事件通知系统比这些替代方案更容易扩展。这允许 APISIX 实时同步配置，使代码简洁，并避免单点故障。

- 完全动态
- 支持[热加载插件](./terminology/plugin.md#热加载)。

## APISIX 所展现出的性能如何？

与其它 API 网关相比，Apache APISIX 提供了更好的性能，其单核 QPS 高达 18,000，平均延迟仅为 0.2 ms。

如果您想获取性能基准测试的具体结果，请查看 [benchmark](benchmark.md)。

## Apache APISIX 支持哪些平台？

Apache APISIX 是一个开源的云原生 API 网关，它支持在裸金属服务器上运行，也支持在 Kubernetes 上使用，甚至也可以运行在 Apple Silicon ARM 芯片上。

## 如何理解“Apache APISIX 是全动态的”？

Apache APISIX 是全动态的 API 网关，意味着当你在更改一个配置后，只需要重新加载配置文件就可以使其生效。

APISIX 可以动态处理以下行为：

- 重新加载插件
- 代理重写
- 对请求进⾏镜像复制
- 对请求进⾏修改
- 健康状态的检查
- 动态控制指向不同上游服务的流量⽐

## APISIX 是否有控制台界面？

APISIX 具有功能强大的 Dashboard，并且 [APISIX Dashboard](https://github.com/apache/apisix-dashboard) 是一个独立的项目。你可以通过 [APISIX Dashboard](https://github.com/apache/apisix-dashboard) 用户操作界面来部署 APISIX Dashboard。

## 我可以为 Apache APISIX 开发适合自身业务的插件吗？

当然可以，APISIX 提供了灵活的自定义插件，方便开发者和企业编写自己的逻辑。

如果你想开发符合自身业务逻辑的插件，请参考：[如何开发插件](plugin-develop.md)。

## 为什么 Apache APISIX 选择 etcd 作为配置中心？

对于配置中心，配置存储只是最基本功能，APISIX 还需要下面几个特性：

1. 集群中的分布式部署
2. 通过比较来监视业务
3. 多版本并发控制
4. 变化通知
5. 高性能和最小的读/写延迟

etcd 提供了这些特性，并且使它比 PostgreSQL 和 MySQL 等其他数据库更理想。

如果你想了解更多关于 etcd 与其他替代方案的比较，请参考[对比图表](https://etcd.io/docs/latest/learning/why/#comparison-chart)。

## 使用 LuaRocks 安装 Apache APISIX 依赖项时，为什么会导致超时、安装缓慢或安装失败？

可能是因为使用的 LuaRocks 服务器延迟过高。

为了解决这个问题，你可以使用 https_proxy 或者使用 `--server` 参数指定一个更快的 LuaRocks 服务器。

你可以运行如下命令来查看可用的服务器（需要 LuaRocks 3.0+）：

```shell
luarocks config rocks_servers
```

中国大陆用户可以使用 `luarocks.cn` 作为 LuaRocks 的服务器。

以下命令可以帮助你更快速的安装依赖：

```bash
make deps ENV_LUAROCKS_SERVER=https://luarocks.cn
```

如果通过上述操作仍然无法解决问题，可以尝试使用 `--verbose` 参数获取详细的日志来诊断问题。

## 如何构建 APISIX-Base 环境？

有些功能需要引入额外的 NGINX 模块，这就要求 APISIX 需要运行在 APISIX-Base 上。如果你需要这些功能，你可以参考 [api7/apisix-build-tools](https://github.com/api7/apisix-build-tools) 中的代码，构建自己的 APISIX-Base 环境。

## 我该如何使用 Apache APISIX 进行灰度发布？

举个例子，比如：`foo.com/product/index.html?id=204&page=2`，并考虑您需要根据查询字符串中的 `id` 在此条件下进行灰度发布：

1. Group A：`id <= 1000`
2. Group B：`id > 1000`

在 Apache APISIX 中有两种不同的方法来实现这一点：

1. 创建一个[Route](terminology/route.md)并配置 `vars` 字段：

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

更多 `lua-resty-radixtree` 匹配操作，请参考：[lua-resty-radixtree](https://github.com/api7/lua-resty-radixtree#operator-list)。

2、通过 [traffic-split](plugins/traffic-split.md) 插件来实现。

## 我如何通过 Apache APISIX 实现从 HTTP 自动跳转到 HTTPS？

比如，将 `http://foo.com` 重定向到 `https://foo.com`。

Apache APISIX 提供了几种不同的方法来实现：

1. 在 [redirect](plugins/redirect.md) 插件中将 `http_to_https` 设置为 `true`：

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

## 我应该如何更改 Apache APISIX 的日志等级？

Apache APISIX 默认的日志等级为 `warn`，你需要将日志等级调整为 `info` 来查看 `core.log.info` 的打印结果。

你需要将 `./conf/config.yaml` 中的 `nginx_config` 配置参数 `error_log_level: "warn"` 修改为 `error_log_level: "info"`，然后重新加载 Apache APISIX 使其生效。

```yaml
nginx_config:
  error_log_level: "info"
```

## 我应该如何重新加载 Apache APISIX 的自定义插件？

所有的 Apache APISIX 的插件都支持热加载的方式。

如果你想了解更多关于热加载的内容，请参考[热加载](./terminology/plugin.md#热加载)。

## 在处理 HTTP 或 HTTPS 请求时，我该如何配置 Apache APISIX 来监听多个端口？

默认情况下，APISIX 在处理 HTTP 请求时只监听 9080 端口。

要配置 Apache APISIX 监听多个端口，你可以：

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

2. 重启或者重新加载 APISIX。

## APISIX 如何利用 etcd 如何实现毫秒级别的配置同步？

Apache APISIX 使用 etcd 作为它的配置中心。etcd 提供以下订阅功能（比如：[watch](https://github.com/api7/lua-resty-etcd/blob/master/api_v3.md#watch)、[watchdir](https://github.com/api7/lua-resty-etcd/blob/master/api_v3.md#watchdir)）。它可以监视对特定关键字或目录的更改。

APISIX 主要使用 [etcd.watchdir](https://github.com/api7/lua-resty-etcd/blob/master/api_v3.md#watchdir) 监视目录内容变更：

- 如果监听目录没有数据更新：则该调用会被阻塞，直到超时或其他错误返回。

- 如果监听目录有数据更新：etcd 将立刻返回订阅（毫秒级）到的新数据，APISIX 将它更新到内存缓存。

## 我应该如何自定义 APISIX 实例 id？

默认情况下，APISIX 从 `conf/apisix.uid` 中读取实例 id。如果找不到，且没有配置 id，APISIX 会生成一个 `uuid` 作为实例 id。

要指定一个有意义的 id 来绑定 Apache APISIX 到你的内部系统，请在你的 `./conf/config.yaml` 中设置 id：

```yaml
apisix:
  id: "your-id"
```

## 为什么 `error.log` 中会出现 "failed to fetch data from etcd, failed to read etcd dir, etcd key: xxxxxx" 的错误？

请按照以下步骤进行故障排除：

1. 确保 Apache APISIX 和集群中的 etcd 部署之间没有任何网络问题。
2. 如果网络正常，请检查是否为 etcd 启用了[gRPC gateway](https://etcd.io/docs/v3.4.0/dev-guide/api_grpc_gateway/)。默认状态取决于你是使用命令行还是配置文件来启动 etcd 服务器。

- 如果使用命令行选项，默认启用 gRPC 网关。可以手动启用，如下所示：

```shell
etcd --enable-grpc-gateway --data-dir=/path/to/data
```

**注意**：当运行 `etcd --help` 时，这个参数不会显示。

- 如果使用配置文件，默认关闭 gRPC 网关。你可以手动启用，如下所示：

  在 `etcd.json` 配置：

```json
{
    "enable-grpc-gateway": true,
    "data-dir": "/path/to/data"
}
```

  在 `etcd.conf.yml` 配置

```yml
enable-grpc-gateway: true
```

**注意**：事实上这种差别已经在 etcd 的 master 分支中消除，但并没有向后兼容到已经发布的版本中，所以在部署 etcd 集群时，依然需要小心。

## 我应该如何创建高可用的 Apache APISIX 集群？

Apache APISIX 可以通过在其前面添加一个负载均衡器来实现高可用性，因为 APISIX 的数据面是无状态的，并且可以在需要时进行扩展。

Apache APISIX 的控制平面是依赖于 `etcd cluster` 的高可用实现的，它只依赖于 etcd 集群。

## 为什么使用源码安装 Apache APISIX 时，执行 `make deps` 命令会失败？

当使用源代码安装 Apache APISIX 时，执行 `make deps` 命令可能会出现如下错误：

```shell
$ make deps
......
Error: Failed installing dependency: https://luarocks.org/luasec-0.9-1.src.rock - Could not find header file for OPENSSL
  No file openssl/ssl.h in /usr/local/include
You may have to install OPENSSL in your system and/or pass OPENSSL_DIR or OPENSSL_INCDIR to the luarocks command.
Example: luarocks install luasec OPENSSL_DIR=/usr/local
make: *** [deps] Error 1
```

这是由于缺少 OpenResty openssl 开发工具包。要安装它，请参考[installation dependencies](install-dependencies.md)。

## 我如何通过 APISIX 代理访问 APISIX Dashboard？

你可以按照以下步骤进行配置：

1. 为 Apache APISIX 代理和 Admin API 配置不同的端口，或者禁用 Admin API。

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

**注意**: Apache APISIX Dashboard 正在监听 `127.0.0.1:9000`。

## 如何使用正则表达式 (regex) 匹配 Route 中的 `uri`？

你可以在 Route 中使用 `vars` 字段来匹配正则表达式：

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

如果你想了解 `vars` 字段的更多信息，请参考 [lua-resty-expr](https://github.com/api7/lua-resty-expr)。

## Upstream 节点是否支持配置 [FQDN](https://en.wikipedia.org/wiki/Fully_qualified_domain_name) 地址？

这是支持的，下面是一个 `FQDN` 为 `httpbin.default.svc.cluster.local`（一个 Kubernetes Service）的示例：

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

使用如下命令测试路由：

```shell
curl http://127.0.0.1:9080/ip -i
```

## Admin API 的 `X-API-KEY` 指的是什么？是否可以修改？

Admin API 的 `X-API-KEY` 指的是 `./conf/config.yaml` 文件中的 `apisix.admin_key.key`，默认值是 `edd1c9f034335f136f87ad84b625c8f1`。它是 Admin API 的访问 token。

默认情况下，它被设置为 `edd1c9f034335f136f87ad84b625c8f1`，也可以通过修改 `./conf/conf/config` 中的参数来修改，如下示例：

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
curl -i http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: newkey' -X PUT -d '
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

**注意**：通过使用默认令牌，可能会面临安全风险。在将其部署到生产环境时，需要对其进行更新。

## 如何允许所有 IP 访问 Apache APISIX 的 Admin API？

Apache APISIX 默认只允许 `127.0.0.0/24` 的 IP 段范围访问 `Admin API`，

如果你想允许所有的 IP 访问，只需在 `./conf/config.yaml` 配置文件中添加如下的配置，然后重启或重新加载 APISIX 就可以让所有 IP 访问 `Admin API`。

```yaml
apisix:
  allow_admin:
    - 0.0.0.0/0
```

**注意**：你可以在非生产环境中使用此方法，以允许所有客户端从任何地方访问 Apache APISIX 实例，但是在生产环境中该设置并不安全。在生产环境中，请仅授权特定的 IP 地址或地址范围访问 Apache APISIX 实例。

## 如何基于 acme.sh 自动更新 APISIX SSL 证书？

你可以运行以下命令来实现这一点：

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

详细步骤，请参考 [APISIX 基于 acme.sh 自动更新 HTTPS 证书](https://juejin.cn/post/6965778290619449351)。

## 在 Apache APISIX 中，我如何在转发到上游之前从路径中删除一个前缀？

在转发至上游之前移除请求路径中的前缀，比如说从 `/foo/get` 改成 `/get`，可以通过 `[proxy-rewrite](plugins/proxy-rewrite.md)` 插件来实现：

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

测试这个配置：

```shell
curl http://127.0.0.1:9080/foo/get -i
HTTP/1.1 200 OK
...
{
  ...
  "url": "http://127.0.0.1/get"
}
```

## 我应该如何解决 `unable to get local issuer certificate` 这个错误？

你可以手动设置证书的路径，将其添加到 `./conf/config.yaml` 文件中，具体操作如下所示：

```yaml
apisix:
  ssl:
    ssl_trusted_certificate: /path/to/certs/ca-certificates.crt
```

**注意：**当你尝试使用 cosocket 连接任何 TLS 服务时，如果 APISIX 不信任对端 TLS 服务证书，都需要配置 `apisix.ssl.ssl_trusted_certificate`。

例如：如果在 APISIX 中使用 Nacos 作为服务发现时，Nacos 开启了 TLS 协议，即 Nacos 配置的 `host` 是 `https://` 开头，就需要配置 `apisix.ssl.ssl_trusted_certificate`，并且使用和 Nacos 相同的 CA 证书。

## 我应该如何解决 `module 'resty.worker.events' not found` 这个错误？

引起这个错误的原因是在 `/root` 目录下安装了 APISIX。因为 worker 进程的用户是 nobody，无权访问 `/root` 目录下的文件。

解决办法是改变 APISIX 的安装目录，推荐安装在 `/usr/local` 目录下。

## 在 Apache APISIX 中，`plugin-metadata` 和 `plugin-configs` 有什么区别？

两者之间的差异如下：

| `plugin-metadata`                                                                                                | `plugin-config`                                                                                                                                     |
| ---------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| 当更改该 Plugin 属性后，需要应用到配置该插件的所有路由上时使用。 | 当你需要复用一组通用的插件配置时使用，可以把 Plugin 配置提取到一个 `plugin-config` 并绑定到不同的路由。 |
| 对绑定到 Plugin 的配置实例的所有实体生效。                           | 对绑定到 `plugin-config` 的路由生效。                                                                                               |
| 对绑定到 Plugin 的配置实例的所有实体生效。                           | 对绑定到 `plugin-config` 的路由生效。                                                                                               |

## 如果在使用 APISIX 过程中遇到问题，我可以在哪里寻求更多帮助？

- [Apache APISIX Slack Channel](/docs/general/join/#加入-slack-频道)：加入后请选择 channel-apisix 频道，即可通过此频道进行 APISIX 相关问题的提问。
- [邮件列表](/docs/general/join/#订阅邮件列表)：任何问题或对项目提议都可以通过社区邮件进行讨论。
- [GitHub Issues](https://github.com/apache/apisix/issues?q=is%3Aissue+is%3Aopen+sort%3Aupdated-desc) 与 [GitHub Discussions](https://github.com/apache/apisix/discussions)：也可直接在 GitHub 中进行相关 issue 创建进行问题的表述。
