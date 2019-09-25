[中文](proxy-rewrite-cn.md)
# proxy-rewrite

upstream proxy info rewrite plugin.

### Parameters
|Name    |Must|Description|
|-------         |-----|------|
|scheme          |No| Upstream new `schema` forwarding protocol,options can be `http` or `https`,default `http`.|
|uri             |No| Upstream new `uri` forwarding address.|
|host            |No| Upstream new `host` forwarding address, can be `192.168.80.128:8080` or `192.168.80.128` format, not set up port default `80`, priority over `upstream.nodes` configuration. |
|enable_websocket|No| enable `websocket`(boolean), default disable.|

### Example

#### Enable Plugin
Here's an example, enable the proxy rewrite plugin on the specified route:

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/test/index.html",
    "plugins": {
        "proxy-rewrite": {
            "uri": "/test/home.html",
            "scheme": "http",
            "host": "192.168.80.128:8080",
            "enable_websocket": true
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:80": 1
        }
    }
}'
```

#### Test Plugin
Testing based on the above examples, add the access log output upstream information variable 
`$upstream_scheme $upstream_addr $upstream_uri` to the nginx configuration file before testing :
```shell
curl -X GET http://127.0.0.1:9080/test/index.html
```

Send the request and see `access.log', if the output information is consistent with the configuration :
```
127.0.0.1 - - [25/Sep/2019:19:35:58 +0800] 127.0.0.1:9080 "GET /test/index.html HTTP/1.1" 200 38 0.007 
"-" "curl/7.29.0" http 192.168.80.128:8080 /test/home.html 200 0.007
```

This means that the proxy rewrite plugin is in effect.

#### Disable Plugin
When you want to disable the proxy rewrite plugin, it is very simple,
 you can delete the corresponding json configuration in the plugin configuration,
  no need to restart the service, it will take effect immediately :
```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/test/index.html",
    "plugins": {},
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:80": 1
        }
    }
}'
```

The proxy rewrite plugin has been disabled now. It works for other plugins.
