# Stream Proxy

TCP is the protocol for many popular applications and services, such as LDAP, MySQL, and RTMP. UDP (User Datagram Protocol) is the protocol for many popular non-transactional applications, such as DNS, syslog, and RADIUS.

APISIX can dynamic load balancing TCP/UDP proxy. In NGINX world, we call TCP/UDP proxy to stream proxy, we followed this statement.

## How to enable Stream proxy?

Setting the `stream_proxy` option in `conf/config.yaml`, specify a list of addresses that require dynamic proxy.
By default, no any stream proxy is enabled.

```
apisix:
  stream_proxy:                 # TCP/UDP proxy
    tcp:                        # TCP proxy address list
      - 9100
      - 127.0.0.1:9101
    udp:                        # UDP proxy address list
      - 9200
      - 127.0.0.1:9211
```

## How to set route?

Here is a mini example:

```shell
curl http://127.0.0.1:9080/apisix/admin/stream_routes/1 -X PUT -d '
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

For more use cases, please take a look at [test case](../t/stream-node/sanity.t).

