[English](plugins.md)

## 热加载

APISIX 的插件是热加载的，不管你是新增、删除还是修改插件，都不需要重启服务。

只需要通过 admin API 发送一个 HTTP 请求即可：
```shell
curl http://127.0.0.1:9080/apisix/admin/plugins/reload -X PUT
```
