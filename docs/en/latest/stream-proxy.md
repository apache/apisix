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

TCP is the protocol for many popular applications and services, such as LDAP, MySQL, and RTMP. UDP (User Datagram Protocol) is the protocol for many popular non-transactional applications, such as DNS, syslog, and RADIUS.

APISIX can dynamically load balancing TCP/UDP proxy. In Nginx world, we call TCP/UDP proxy to stream proxy, we followed this statement.

## How to enable stream proxy?

Setting the `stream_proxy` option in `conf/config.yaml`, specify a list of addresses that require dynamic proxy.
By default, no stream proxy is enabled.

```yaml
apisix:
  stream_proxy: # TCP/UDP proxy
    tcp: # TCP proxy address list
      - 9100
      - "127.0.0.1:9101"
    udp: # UDP proxy address list
      - 9200
      - "127.0.0.1:9211"
```

If `apisix.enable_admin` is true, both HTTP and stream proxy are enabled with the configuration above.

If you have set the `enable_admin` to false, and need to enable both HTTP and stream proxy, set the `only` to false:

```yaml
apisix:
  enable_admin: false
  stream_proxy: # TCP/UDP proxy
    only: false
    tcp: # TCP proxy address list
      - 9100
```

## How to set route?

Here is a mini example:

```shell
curl http://127.0.0.1:9080/apisix/admin/stream_routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

It means APISIX will proxy the request to `127.0.0.1:1995` which the client remote address is `127.0.0.1`.

For more use cases, please take a look at [test case](https://github.com/apache/apisix/blob/master/t/stream-node/sanity.t).

## More route match options

And we can add more options to match a route. Currently stream route configuration supports 3 fields for filtering:

- server_addr: The address of the APISIX server that accepts the L4 stream connection.
- server_port: The port of the APISIX server that accepts the L4 stream connection.
- remote_addr: The address of client from which the request has been made.

Here is an example:

```shell
curl http://127.0.0.1:9080/apisix/admin/stream_routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

Let's take another real world example:

1. Put this config inside `config.yaml`

   ```yaml
   apisix:
     stream_proxy: # TCP/UDP proxy
       tcp: # TCP proxy address list
         - 9100 # by default uses 0.0.0.0
         - "127.0.0.10:9101"
   ```

2. Now run a mysql docker container and expose port 3306 to the host

   ```shell
   $ docker run --name mysql -e MYSQL_ROOT_PASSWORD=toor -p 3306:3306 -d mysql
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
   curl http://127.0.0.1:9080/apisix/admin/stream_routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
curl http://127.0.0.1:9080/apisix/admin/stream_routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
curl http://127.0.0.1:9080/apisix/admin/stream_routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
curl http://127.0.0.1:9080/apisix/admin/stream_routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

By setting the `scheme` to "tls", APISIX will do TLS handshake with the upstream.

When the client is also speaking TLS over TCP, the SNI from the client will pass through to the upstream. Otherwise, a dummy SNI "apisix_backend" will be used.
