[English](proxy-rewrite.md)
# proxy-rewrite

上游代理信息重写插件。

#### 配置参数
|名字    |可选|说明|
|-------         |-----|------|
|scheme          |可选| 转发到上游的新`schema` 协议，可以是`http`或`https`，默认`http`协议|
|uri             |可选| 转发到上游的新`uri` 地址|
|host            |可选| 转发到上游的新`host` 地址，格式可以为`192.168.80.128:8080`或`192.168.80.128`如果未设置端口将默认设置为`80`，此配置优先级将高于`upstream.nodes` |
|enable_websocket|可选| 是否启用`websocket`（布尔值），默认不启用|

### 示例

#### 开启插件
下面是一个示例，在指定的 route 上开启了 proxy rewrite 插件:

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

#### 测试插件
基于上述配置进行测试，测试前在 Nginx 配置文件 access 日志输出配置中补充 `$upstream_scheme $upstream_addr $upstream_uri` 变量。
```shell
curl -X GET http://127.0.0.1:9080/test/index.html
```

发送请求，查看 `access.log`，如果输出信息与配置一致：
```
127.0.0.1 - - [25/Sep/2019:19:35:58 +0800] 127.0.0.1:9080 "GET /test/index.html HTTP/1.1" 200 38 0.007 
"-" "curl/7.29.0" http 192.168.80.128:8080 /test/home.html 200 0.007
```

即表示 proxy rewrite 插件生效了。

#### 禁用插件
当你想去掉 proxy rewrite 插件的时候，很简单，在插件的配置中把对应的 json 配置删除即可，无须重启服务，即刻生效：

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

现在就已经移除了 proxy rewrite 插件了。其他插件的开启和移除也是同样的方法。
