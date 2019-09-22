[English](limit-conn.md)
# limit-conn

Apisix 的限制并发请求（或并发连接）插件。

### 属性

* `conn`: 允许的最大并发请求数。 超过这个比率的请求(低于“ conn” + “ burst”)将被延迟以符合这个阈值。
* `burst`: 允许延迟的过多并发请求(或连接)的数量。
* `default_conn_delay`: 默认的典型连接(或请求)的处理延迟时间。
* `key`: 用户指定的限制并发级别的关键字，可以是客户端IP或服务端IP。

    例如，可以使用主机名(或服务器区域)作为关键字，以便限制每个主机名的并发性。 否则，我们也可以使用客户端地址作为关键字，这样我们就可以避免单个客户端用太多的并行连接或请求淹没我们的服务。

    现在接受以下关键字: “remote_addr”(客户端的 IP)，“server_addr”(服务器的 IP)，请求头中的“ X-Forwarded-For/X-Real-IP”。

* `rejected_code`: 当请求超过阈值时返回的 HTTP状态码， 默认值是503。

#### 如何启用

下面是一个示例，在指定的 route 上开启了 limit-conn 插件:

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/index.html",
    "id": 1,
    "plugins": {
        "limit-conn": {
            "conn": 1,
            "burst": 0,
            "default_conn_delay": 0.1,
            "rejected_code": 503,
            "key": "remote_addr"
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "39.97.63.215:80": 1
        }
    }
}'
```

你可以使用浏览器打开 dashboard：`http://127.0.0.1:9080/apisix/dashboard/`，通过 web 界面来完成上面的操作，先增加一个 route：
![](../images/plugin/limit-conn-1.png)

然后在 route 页面中添加 limit-conn 插件：
![](../images/plugin/limit-conn-2.png)

#### test plugin

上面启用的插件的参数表示只允许一个并发请求。 当收到多个并发请求时，将直接返回 503 拒绝请求。

```shell
curl -i http://127.0.0.1:9080/index.html?sleep=20 &

curl -i http://127.0.0.1:9080/index.html?sleep=20
<html>
<head><title>503 Service Temporarily Unavailable</title></head>
<body>
<center><h1>503 Service Temporarily Unavailable</h1></center>
<hr><center>openresty</center>
</body>
</html>
```

这就表示 limit-conn 插件生效了。

#### 移除插件

当你想去掉 limit-conn 插件的时候，很简单，在插件的配置中把对应的 json 配置删除即可，无须重启服务，即刻生效：

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/index.html",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "39.97.63.215:80": 1
        }
    }
}'
```

现在就已经移除了 limit-conn 插件了。其他插件的开启和移除也是同样的方法。

