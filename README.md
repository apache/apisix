# Summary

# Design Doc

### How to load the plugin?

![](doc/flow-load-plugin.png)


# Development

### Source Install

> Dependent library

* [lua-resty-r3] Setups the [resty-r3#install](https://github.com/iresty/lua-resty-r3#install) library.
* [lua-resty-etcd] Setups the [resty-etcd#install](https://github.com/iresty/lua-resty-etcd#install) library.
* [lua-resty-balancer] Setups the [resty-balancer#install](https://github.com/iresty/lua-resty-balancer#installation) library.

> Install by luarocks

```shell
luarocks install lua-resty-r3 lua-resty-etcd lua-resty-balancer
```

### User routes with plugins config in etcd

Here is example for one route and one upstream:

```shell
$ curl http://127.0.0.1:2379/v2/keys/user_routes/1 | python -m json.tool
{
    "action": "get",
    "node": {
        "createdIndex": 649,
        "key": "/user_routes/1",
        "modifiedIndex": 649,
        "value": "{\"host\":\"test.com\",\"methods\":[\"GET\"],\"uri\":\"/hello\",\"id\":3333,\"plugin_config\":{\"example-plugin\":{\"i\":1,\"s\":\"s\",\"t\":[1,2]},\"new-plugin\":{\"a\":\"a\"}},\"upstream\":{\"id\":1,\"type\":\"roundrobin\"}}"
    }
}

$ curl http://127.0.0.1:2379/v2/keys/user_upstreams/1 | python -m json.tool
{
    "action": "get",
    "node": {
        "createdIndex": 679,
        "key": "/user_upstreams/1",
        "modifiedIndex": 679,
        "value": "{\"id\":1,\"type\":\"roundrobin\",\"nodes\":{\"220.181.57.215:80\":1,\"220.181.57.216:80\":1,\"220.181.57.217:80\":1}}"
    }
}
```

Here is example for one route (it contains the upstream information):

```
$ curl http://127.0.0.1:2379/v2/keys/user_routes/1 | python -m json.tool
{
    "action": "get",
    "node": {
        "createdIndex": 649,
        "key": "/user_routes/1",
        "modifiedIndex": 649,
        "value": "{\"host\":\"test.com\",\"methods\":[\"GET\"],\"uri\":\"/hello\",\"id\":3333,\"plugin_config\":{\"example-plugin\":{\"i\":1,\"s\":\"s\",\"t\":[1,2]},\"new-plugin\":{\"a\":\"a\"}},\"upstream\":{\"type\":\"roundrobin\",\"nodes\":{\"220.181.57.215:80\":1,\"220.181.57.216:80\":1,\"220.181.57.217:80\":1}}}"
    }
}
```
