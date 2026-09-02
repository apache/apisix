---
title: Stream Proxy
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

A stream proxy operates at the transport layer, handling stream-oriented traffic based on TCP and UDP protocols. TCP is used for many applications and services, such as LDAP, MySQL, and RTMP. UDP is used for many popular non-transactional applications, such as DNS, syslog, and RADIUS.

APISIX can serve as a stream proxy, in addition to being an application layer proxy.

## How to enable stream proxy?

By default, stream proxy is disabled.

To enable this option, set `apisix.proxy_mode` to `stream` or `http&stream`, depending on whether you want stream proxy only or both http and stream. Then add the `apisix.stream_proxy` option in `conf/config.yaml` and specify the list of addresses where APISIX should act as a stream proxy and listen for incoming requests.

```yaml
apisix:
  proxy_mode: http&stream  # enable both http and stream proxies
  stream_proxy:
    tcp:
      - 9100 # listen on 9100 ports of all network interfaces for TCP requests
      - "127.0.0.1:9101"
    udp:
      - 9200 # listen on 9200 ports of all network interfaces for UDP requests
      - "127.0.0.1:9211"
```

If `apisix.stream_proxy` is undefined in `conf/config.yaml`, you will encounter an error similar to the following and not be able to add a stream route:

```
{"error_msg":"stream mode is disabled, can not add stream routes"}
```

## How to set a route?

You can create a stream route using the Admin API `/stream_routes` endpoint. For example:

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/stream_routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "remote_addr": "192.168.5.3",
    "upstream": {
        "nodes": {
            "192.168.4.10:1995": 1
        },
        "type": "roundrobin"
    }
}'
```

With this configuration, APISIX would only forward the request to the upstream service at `192.168.4.10:1995` if and only if the request is sent from `192.168.5.3`. See the next section to learn more about filtering options.

More examples can be found in [test cases](https://github.com/apache/apisix/blob/master/t/stream-node/sanity.t).

## More stream route filtering options

Currently there are three attributes in stream routes that can be used for filtering requests:

- `server_addr`: The address of the APISIX server that accepts the L4 stream connection.
- `server_port`: The port of the APISIX server that accepts the L4 stream connection.
- `remote_addr`: The address of client from which the request has been made.

Here is an example:

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

It means APISIX will proxy the request to `127.0.0.1:1995` when the server address is `127.0.0.1` and the server port is equal to `2000`.

Here is an example with MySQL:

1. Put this config inside `config.yaml`

   ```yaml
   apisix:
     proxy_mode: http&stream  # enable both http and stream proxies
     stream_proxy: # TCP/UDP proxy
       tcp: # TCP proxy address list
         - 9100 # by default uses 0.0.0.0
         - "127.0.0.10:9101"
   ```

2. Now run a mysql docker container and expose port 3306 to the host

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

3. Now we are going to create a stream route with server filtering:

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

   It only forwards the request to the mysql upstream whenever a connection is received at APISIX server `127.0.0.10` and port `9101`. Let's test that behaviour:

4. Making a request to 9100 (stream proxy port enabled inside config.yaml), filter matching fails.

   ```shell
   $ mysql --host=127.0.0.1 --port=9100 -u root -p
   Enter password:
   ERROR 2013 (HY000): Lost connection to MySQL server at 'reading initial communication packet', system error: 2

   ```

   Instead making a request to the APISIX host and port where the filter matching succeeds:

   ```shell
   mysql --host=127.0.0.10 --port=9101 -u root -p
   Enter password:
   Welcome to the MySQL monitor.  Commands end with ; or \g.
   Your MySQL connection id is 26
   ...
   mysql>
   ```

Read [Admin API's Stream Route section](./admin-api.md#stream-route) for the complete options list.

## Accept TLS over TCP connection

APISIX can accept TLS over TCP connection.

First of all, we need to enable TLS for the TCP address:

```yaml
apisix:
  proxy_mode: http&stream  # enable both http and stream proxies
  stream_proxy: # TCP/UDP proxy
    tcp: # TCP proxy address list
      - addr: 9100
        tls: true
```

Second, we need to configure certificate for the given SNI.
See [Admin API's SSL section](./admin-api.md#ssl) for how to do.
mTLS is also supported, see [Protect Route](./mtls.md#protect-route) for how to do.

Third, we need to configure a stream route to match and proxy it to the upstream:

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

When the connection is TLS over TCP, we can use the SNI to match a route, like:

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

In this case, a connection handshaked with SNI `a.test.com` will be proxied to `127.0.0.1:5991`.

## Proxy to TLS over TCP upstream

APISIX also supports proxying to TLS over TCP upstream.

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

By setting the `scheme` to `tls`, APISIX will do TLS handshake with the upstream.

When the client is also speaking TLS over TCP, the SNI from the client will pass through to the upstream. Otherwise, a dummy SNI `apisix_backend` will be used.

## TLS passthrough

The two sections above both terminate the client's TLS handshake at APISIX. With `tls_passthrough`, APISIX instead forwards the encrypted stream to the upstream untouched, and still picks the upstream from the SNI, which it reads out of the prereaded `ClientHello` (`ssl_preread on`) rather than out of a handshake it performed itself:

```yaml
apisix:
  proxy_mode: http&stream
  stream_proxy:
    tcp:
      - addr: 9100
        tls_passthrough: true
```

The upstream terminates the handshake, so on such a port:

- payload-inspecting stream plugins (`mqtt-proxy`, `xrpc`, `redis`) have nothing to read, and gateway mTLS does not apply — client certificate verification moves to the upstream;
- an upstream with `"scheme": "tls"` is rejected with a `503`, because a second handshake would send the client's `ClientHello` to the upstream as payload.

Routing is otherwise unchanged, so a stream route matches by SNI exactly as it does for a terminating port:

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

### Deciding per route on a mixed port

Setting both flags on one listen opens a **mixed** port, where each connection is terminated or passed through according to `tls_passthrough` on the stream route it matches (a boolean, `false` by default):

```yaml
apisix:
  proxy_mode: http&stream
  stream_proxy:
    tcp:
      - addr: 9100
        tls: true
        tls_passthrough: true
```

```shell
# passed through to the upstream, which terminates the handshake
curl http://127.0.0.1:9180/apisix/admin/stream_routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "sni": "a.test.com",
    "tls_passthrough": true,
    "upstream": {
        "nodes": {
            "127.0.0.1:5991": 1
        },
        "type": "roundrobin"
    }
}'

# terminated by APISIX, using the certificate configured for this SNI
curl http://127.0.0.1:9180/apisix/admin/stream_routes/2 -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "sni": "b.test.com",
    "upstream": {
        "nodes": {
            "127.0.0.1:5992": 1
        },
        "type": "roundrobin"
    }
}'
```

The route flag comes from etcd, so moving a service between the two modes needs no configuration change or restart.

A port itself cannot be both: `ssl_preread on` and `listen ... ssl` are configuration-time directives, and on one server the handshake consumes the `ClientHello` before the preread phase can read it. So the two behaviours live in internal servers reachable over unix sockets under `logs/`, and the preread phase of the public listen picks between them. Note that:

- only mixed ports pay that extra hop; a `tls: true` or `tls_passthrough: true` port keeps its direct path;
- the client address crosses the hop in a PROXY protocol header restored with `set_real_ip_from unix:`, so route matching, stream plugins and logs see the real peer. A local user able to connect to those sockets could forge that header, so keep `logs/` off limits to untrusted local users — as it already has to be for `stream_worker_events.sock`;
- `apisix_stream_metrics_zone` counts nginx sessions and has no per-server switch, so a mixed port counts each client connection twice.

Two `stream_proxy.tcp` entries on the same address must agree on their TLS mode and on `proxy_protocol_to_upstream`; otherwise they would need different nginx `server` blocks on one address, and APISIX rejects the configuration at startup.

## PROXY protocol

APISIX can accept the [PROXY protocol](https://www.haproxy.org/download/1.8/doc/proxy-protocol.txt) on TCP stream ports and forward it to the upstream.

The `apisix.proxy_protocol` options set the default for **all** TCP stream ports:

```yaml
apisix:
  proxy_protocol:
    enable_tcp_pp: true              # accept the PROXY protocol from the client
    enable_tcp_pp_to_upstream: true  # send the PROXY protocol to the upstream
  proxy_mode: http&stream
  stream_proxy:
    tcp:
      - 9100
      - 9101
```

To control the PROXY protocol per port, set `proxy_protocol` and/or `proxy_protocol_to_upstream` on a `stream_proxy.tcp` entry. The per-port value overrides the global default for that port:

```yaml
apisix:
  proxy_protocol:
    enable_tcp_pp: true              # default for ports that don't set `proxy_protocol`
  proxy_mode: http&stream
  stream_proxy:
    tcp:
      - addr: 9100                          # accepts the PROXY protocol (inherits the global default)
      - addr: 9101
        proxy_protocol: false               # opt this port out of accepting the PROXY protocol
      - addr: 9102
        proxy_protocol_to_upstream: true    # also send the PROXY protocol to the upstream
```

The accept side (`proxy_protocol`) is a per-listen directive, so ports with different settings can share one listener. The upstream side (`proxy_protocol_to_upstream`) is a server-level directive, so APISIX renders ports that send the PROXY protocol upstream into a separate `server` block. UDP listens never send the PROXY protocol upstream, so they always stay in the plain `server` block.

:::warning

Only enable `proxy_protocol_to_upstream` for upstreams that expect the PROXY protocol. An upstream that does not will read the plaintext `PROXY` line as application data and typically close the connection immediately — a TLS upstream, for example, cannot parse it as a TLS record.

:::

### Preserving the client address behind a load balancer

`proxy_protocol_to_upstream` builds the outbound header from the address APISIX is connected to. When APISIX sits behind a load balancer that speaks the PROXY protocol, that is the load balancer's address, so accepting a header and sending one is not by itself enough to carry the client address through to the upstream.

Set `nginx_config.stream.real_ip_from` to the addresses of the load balancers you trust. On a connection from a trusted address that carries an inbound PROXY protocol header, APISIX replaces the client address with the one from the header:

```yaml
apisix:
  proxy_mode: http&stream
  stream_proxy:
    tcp:
      - addr: 9100
        proxy_protocol: true              # accept the header from the load balancer
        proxy_protocol_to_upstream: true  # rebuild it toward the upstream
nginx_config:
  stream:
    real_ip_from:
      - 192.168.1.0/24                    # the load balancer's network
```

The header APISIX then sends upstream carries the client address, and so do the stream `$remote_addr`, the access log, and address-based matching such as the `ip-restriction` plugin. The directly connected address stays available as `$realip_remote_addr`.

`real_ip_from` is empty by default and only takes effect on ports that accept the PROXY protocol, and only for peers that match it. Trust only load balancers you control: a peer you trust can claim to be any client.

### Choosing a configuration

Which combination you want depends on who needs to see the client address:

| Configuration | `proxy_protocol` | `proxy_protocol_to_upstream` | `real_ip_from` | Result |
|---|---|---|---|---|
| Pass through | off | off | — | APISIX never looks at the header and proxies it to the upstream as ordinary stream bytes. The upstream sees the client, APISIX does not. Not usable on ports where APISIX has to read the stream itself, such as TLS ports or routes that match on preread data. |
| Terminate | on | off | — | APISIX consumes the header and connects to the upstream without one. Use this for upstreams that do not speak the PROXY protocol. |
| Terminate and rebuild | on | on | load balancer network | APISIX consumes the header and sends a new one carrying the client address. Both APISIX and the upstream see the client. |
| Terminate and rebuild, nothing trusted | on | on | — | The upstream still gets a header, but it carries the address APISIX is connected to — the load balancer — so the client address is lost. |
