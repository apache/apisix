# limit-req
[English](limit-req.md)

限制请求速度的插件，使用的是漏桶算法。

### 参数
* `rate`：指定的请求速率（以秒为单位），请求速率超过 `rate` 但没有超过 （`rate` + `brust`）的请求会被加上延时
* `burst`：请求速率超过 （`rate` + `brust`）的请求会被直接拒绝
* `rejected_code`：当请求超过阈值被拒绝时，返回的 HTTP 状态码
* `key`：是用来做请求计数的依据，当前只接受终端 IP 做为 key，即 "remote_addr"

### 示例

#### 开启插件
下面是一个示例，在指定的 route 上开启了 limit req 插件:

```shell
curl http://127.0.0.1:2379/v2/keys/apisix/routes/1 -X PUT -d value='
{
	"methods": ["GET"],
	"uri": "/index.html",
	"id": 1,
	"plugin_config": {
		"limit-req": {
			"rate": 1,
			"burst": 2,
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

#### 测试插件
上述配置限制了每秒请求速率为 1，大于 1 小于 3 的会被加上延时，速率超过 3 就会被拒绝：
```shell
curl -i http://127.0.0.1:9080/index.html
```

当你超过，就会收到包含 503 返回码的响应头：
```
HTTP/1.1 503 Service Temporarily Unavailable
Content-Type: text/html
Content-Length: 194
Connection: keep-alive
Server: APISIX web server

<html>
<head><title>503 Service Temporarily Unavailable</title></head>
<body>
<center><h1>503 Service Temporarily Unavailable</h1></center>
<hr><center>openresty</center>
</body>
</html>
```

这就表示 limit req 插件生效了。

#### 移除插件
当你想去掉 limit req 插件的时候，很简单，在插件的配置中把对应的 json 配置删除即可，无须重启服务，即刻生效：

```shell
curl http://127.0.0.1:2379/v2/keys/apisix/routes/1 -X PUT -d value='
{
	"methods": ["GET"],
	"uri": "/index.html",
	"id": 1,
	"plugin_config": {
	},
	"upstream": {
		"type": "roundrobin",
		"nodes": {
			"39.97.63.215:80": 1
		}
	}
}'
```

现在就已经移除了 limit req 插件了。其他插件的开启和移除也是同样的方法。
