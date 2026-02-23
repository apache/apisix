---
title: TCP/UDP 动态代理
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

众多的闻名的应用和服务，像 LDAP、MYSQL 和 RTMP，选择 TCP 作为通信协议。但是像 DNS、syslog 和 RADIUS 这类非事务性的应用，他们选择了 UDP 协议。

APISIX 可以对 TCP/UDP 协议进行代理并实现动态负载均衡。在 nginx 世界，称 TCP/UDP 代理为 stream 代理，在 APISIX 这里我们也遵循了这个声明。

## 如何开启 Stream 代理

要启用该选项，请将 `apisix.proxy_mode` 设置为 `stream` 或 `http&stream`，具体取决于您是只需要 stream 代理还是需要 http 和 stream。然后在 `conf/config.yaml` 中添加 `apisix.stream_proxy` 选项并指定 APISIX 应充当 stream 代理并侦听传入请求的地址列表。

```yaml
apisix:
  proxy_mode: http&stream  # enable both http and stream proxies
  stream_proxy: # TCP/UDP proxy
    tcp: # TCP proxy address list
      - 9100
      - "127.0.0.1:9101"
    udp: # UDP proxy address list
      - 9200
      - "127.0.0.1:9211"
```

## 如何设置 route

简例如下：

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/stream_routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "remote_addr": "127.0.0.1",
    "upstream": {
        "nodes": {
            "127.0.0.1:1995": 1
        },
        "type": "roundrobin"
    }
}'
```

例子中 APISIX 对客户端 IP 为 `127.0.0.1` 的请求代理转发到上游主机 `127.0.0.1:1995`。
更多用例，请参照 [test case](https://github.com/apache/apisix/blob/master/t/stream-node/sanity.t)。

## 更多 route 匹配选项

我们可以添加更多的选项来匹配 route。目前 Stream Route 配置支持 3 个字段进行过滤：

- server_addr: 接受 Stream Route 连接的 APISIX 服务器的地址。
- server_port: 接受 Stream Route 连接的 APISIX 服务器的端口。
- remote_addr: 发出请求的客户端地址。

例如

```shell
curl http://127.0.0.1:9180/apisix/admin/stream_routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "server_addr": "127.0.0.1",
    "server_port": 2000,
    "upstream": {
        "nodes": {
            "127.0.0.1:1995": 1
        },
        "type": "roundrobin"
    }
}'
```

例子中 APISIX 会把服务器地址为 `127.0.0.1`, 端口为 `2000` 代理到上游地址 `127.0.0.1:1995`。

让我们再举一个实际场景的例子：

1. 将此配置放在 `config.yaml` 中

   ```yaml
   apisix:
     proxy_mode: http&stream  # enable both http and stream proxies
     stream_proxy: # TCP/UDP proxy
       tcp: # TCP proxy address list
         - 9100 # by default uses 0.0.0.0
         - "127.0.0.10:9101"
   ```

2. 现在运行一个 mysql docker 容器并将端口 3306 暴露给主机

   ```shell
   $ docker run --name mysql -e MYSQL_ROOT_PASSWORD=toor -p 3306:3306 -d mysql mysqld --default-authentication-plugin=mysql_native_password
   # check it using a mysql client that it works
   $ mysql --host=127.0.0.1 --port=3306 -u root -p
   Enter password:
   Welcome to the MySQL monitor.  Commands end with ; or \g.
   Your MySQL connection id is 25
   ...
   mysql>
   ```

3. 现在我们将创建一个带有服务器过滤的 stream 路由：

   ```shell
   curl http://127.0.0.1:9180/apisix/admin/stream_routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
   {
       "server_addr": "127.0.0.10",
       "server_port": 9101,
       "upstream": {
           "nodes": {
               "127.0.0.1:3306": 1
           },
           "type": "roundrobin"
       }
   }'
   ```

   每当 APISIX 服务器 `127.0.0.10` 和端口 `9101` 收到连接时，它只会将请求转发到 mysql 上游。让我们测试一下：

4. 向 `9100` 发出请求（在 config.yaml 中启用 stream 代理端口），过滤器匹配失败。

   ```shell
   $ mysql --host=127.0.0.1 --port=9100 -u root -p
   Enter password:
   ERROR 2013 (HY000): Lost connection to MySQL server at 'reading initial communication packet', system error: 2
   ```

  下面的请求匹配到了 stream 路由，所以它可以正常代理到 mysql。

   ```shell
   mysql --host=127.0.0.10 --port=9101 -u root -p
   Enter password:
   Welcome to the MySQL monitor.  Commands end with ; or \g.
   Your MySQL connection id is 26
   ...
   mysql>
   ```

完整的匹配选项列表参见 [Admin API 的 Stream Route](./admin-api.md#stream-route)。

## 接收基于 TCP 的 TLS 连接

APISIX 支持接收基于 TCP 的 TLS 连接。

首先，我们需要给对应的 TCP 地址启用 TLS：

```yaml
apisix:
  proxy_mode: http&stream  # enable both http and stream proxies
  stream_proxy: # TCP/UDP proxy
    tcp: # TCP proxy address list
      - addr: 9100
        tls: true
```

接着，我们需要为给定的 SNI 配置证书。
具体步骤参考 [Admin API 的 SSL](./admin-api.md#ssl)。
mTLS 也是支持的，参考 [保护路由](./mtls.md#保护路由)。

然后，我们需要配置一个 route，匹配连接并代理到上游：

```shell
curl http://127.0.0.1:9180/apisix/admin/stream_routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "upstream": {
        "nodes": {
            "127.0.0.1:1995": 1
        },
        "type": "roundrobin"
    }
}'
```

当连接为基于 TCP 的 TLS 时，我们可以通过 SNI 来匹配路由，比如：

```shell
curl http://127.0.0.1:9180/apisix/admin/stream_routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "sni": "a.test.com",
    "upstream": {
        "nodes": {
            "127.0.0.1:5991": 1
        },
        "type": "roundrobin"
    }
}'
```

在这里，握手时发送 SNI `a.test.com` 的连接会被代理到 `127.0.0.1:5991`。

## 代理到基于 TCP 的 TLS 上游

APISIX 还支持代理到基于 TCP 的 TLS 上游。

```shell
curl http://127.0.0.1:9180/apisix/admin/stream_routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "upstream": {
        "scheme": "tls",
        "nodes": {
            "127.0.0.1:1995": 1
        },
        "type": "roundrobin"
    }
}'
```

通过设置 `scheme` 为 `tls`，APISIX 将与上游进行 TLS 握手。

当客户端也使用基于 TCP 的 TLS 上游时，客户端发送的 SNI 将传递给上游。否则，将使用一个假的 SNI `apisix_backend`。
