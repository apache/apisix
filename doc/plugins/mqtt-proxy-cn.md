[English](mqtt-proxy.md)


# 目录
- [**名字**](#名字)
- [**属性**](#属性)
- [**如何启用**](#如何启用)
- [**禁用插件**](#禁用插件)

## 名字

`mqtt-proxy` 只工作在流模式，它可以帮助你根据 MQTT 的 `client_id` 实现动态负载均衡。

这个插件都支持 MQTT [3.1.* ]( http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html )及[5.0]( https://docs.oasis-open.org/mqtt/mqtt/v5.0/mqtt-v5.0.html )。

## 属性

* `protocol_name`: 必选，协议名称，正常情况下应为“ MQTT” 。
* `protocol_level`: 必选，协议级别，MQTT `3.1.*` 应为 “4” ，MQTT `5.0` 应该是“5”。
* `upstream.ip`: 必选，将当前请求转发到的上游的 IP 地址，
* `upstream.port`: 必选，将当前请求转发到的上游的 端口，

## 如何启用

下面是一个示例，在指定的 route 上开启了 mqtt-proxy 插件:

```shell
curl http://127.0.0.1:9080/apisix/admin/stream_routes/1 -X PUT -d '
{
    "remote_addr": "127.0.0.1",
    "plugins": {
        "mqtt-proxy": {
            "protocol_name": "MQTT",
            "protocol_level": 4,
            "upstream": {
                "ip": "127.0.0.1",
                "port": 1980
            }
        }
    }
}'
```

#### 禁用插件

当你想去掉插件的时候，很简单，在插件的配置中把对应的 json 配置删除即可，无须重启服务，即刻生效：

```shell
$ curl http://127.0.0.1:2379/v2/keys/apisix/stream_routes/1 -X DELETE
```

现在就已经移除了 mqtt-proxy 插件了。