[English](serverless.md)
# serverless
serverless 的插件有两个，分别是 `serverless-pre-function` 和 `serverless-post-function`，
前者会在指定阶段的最开始运行，后者是在指定阶段的最后运行。

这两个插件接收的参数都是一样的。

### Parameters
* `phase`: 指定的运行阶段，没有指定的话默认是 `access`。允许的阶段有：`rewrite`、`access`
`header_filer`、`body_filter`、`log` 和 `balancer` 阶段。
* `functions`: 指定运行的函数列表，是数组类型，里面可以包含一个函数，也可以是多个函数，按照先后顺序执行。
需要注意的是，这里只接受函数，而不接受其他类型的 Lua 代码。比如匿名函数是合法的：
```
return function()
    ngx.log(ngx.ERR, 'one')
end
```

闭包也是合法的：
```
local count = 1
return function()
    count = count + 1
    ngx.say(count)
end
```

但不是函数类型的代码就是非法的：
```
local count = 1
ngx.say(count)
```

### 示例

#### 启动插件
下面是一个示例，在指定的 route 上开启了 serverless 插件:

```shell
curl -i http://127.0.0.1:9080/apisix/admin/routes/1 -X PUT -d '
{
    "uri": "/index.html",
    "plugins": {
        "plugins": {
            "serverless-pre-function": {
                "phase": "rewrite",
                "functions" : ["return function() ngx.log(ngx.ERR, 'serverless pre function'); end"]
            }
        },
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
使用 curl 访问：
```shell
curl -i http://127.0.0.1:9080/index.html
```

然后你在 error.log 日志中就会发现 `serverless pre function` 这个 error 级别的日志，
表示指定的函数已经生效。

#### 移除插件
当你想去掉插件的时候，很简单，在插件的配置中把对应的 json 配置删除即可，无须重启服务，即刻生效：

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

现在就已经移除了 serverless 插件了。其他插件的开启和移除也是同样的方法。
