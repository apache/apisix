# limit-count
[English](limit-count.md)

和 [GitHub API 的限速](https://developer.github.com/v3/#rate-limiting)类似，
在指定的时间范围内，限制总的请求个数。并且在 HTTP 响应头中返回剩余可以请求的个数。

### 参数
* `count`：指定时间窗口内的请求数量阈值
* `time_window`：时间窗口的大小（以秒为单位），超过这个时间就会重置
* `rejected_code`：当请求超过阈值被拒绝时，返回的 HTTP 状态码，默认是 503
* `key`：是用来做请求计数的依据，当前只接受终端 IP 做为 key，即 "remote_addr"

### 示例

#### 开启插件
下面是一个示例，在指定的 route 上开启了 limit count 插件:

```shell
curl http://127.0.0.1:2379/v2/keys/apisix/routes/1 -X PUT -d value='
{
	"methods": ["GET"],
	"uri": "/index.html",
	"id": 1,
	"plugin_config": {
		"limit-count": {
			"count": 2,
			"time_window": 60,
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
上述配置限制了 60 秒内只能访问 2 次，前两次访问都会正常访问：
```shell
curl -i http://127.0.0.1:9080/index.html
```

响应头里面包含了 `X-RateLimit-Limit` 和 `X-RateLimit-Remaining`，他们的含义分别是限制的总请求数和剩余还可以发送的请求数：
```
HTTP/1.1 200 OK
Content-Type: text/html
Content-Length: 13175
Connection: keep-alive
X-RateLimit-Limit: 2
X-RateLimit-Remaining: 0
Server: APISIX web server
```

当你第三次访问的时候，就会收到包含 503 返回码的响应头：
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

这就表示 limit count 插件生效了。

#### 移除插件
当你想去掉 limit count 插件的时候，很简单，在插件的配置中把对应的 json 配置删除即可，无须重启服务，即刻生效：

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

现在就已经移除了 limit count 插件了。其他插件的开启和移除也是同样的方法。
