[中文](proxy-rewrite-cn.md)
# proxy-rewrite

upstream proxy info rewrite plugin.

### Parameters
|Name    |Required|Description|
|-------         |-----|------|
|scheme          |No| Upstream new `schema` forwarding protocol,options can be `http` or `https`,default `http`.|
|uri             |No| Upstream new `uri` forwarding address.|
|host            |No| Upstream new `host` forwarding address, example `iresty.com`. |
|enable_websocket|No| enable `websocket`(boolean), default `false`.|

### Example

#### Enable Plugin
Here's an example, enable the `proxy rewrite` plugin on the specified route:

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/test/index.html",
    "plugins": {
        "proxy-rewrite": {
            "uri": "/test/home.html",
            "scheme": "http",
            "host": "iresty.com",
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
Testing based on the above examples :
```shell
curl -X GET http://127.0.0.1:9080/test/index.html
```

Send the request and see upstream `access.log', if the output information is consistent with the configuration :
```
127.0.0.1 - [26/Sep/2019:10:52:20 +0800] iresty.com GET /test/home.html HTTP/1.1 200 38 - curl/7.29.0 - 0.000 199 107
```

This means that the `proxy rewrite` plugin is in effect.

#### Disable Plugin
When you want to disable the `proxy rewrite` plugin, it is very simple,
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

The `proxy rewrite` plugin has been disabled now. It works for other plugins.
