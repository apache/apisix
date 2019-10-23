[中文](plugins-cn.md)

## Hot reload
APISIX plug-ins are hot-loaded. No matter you add, delete or modify plug-ins, you don't need to restart the service.

Just send an HTTP request through admin API:
```shell
curl http://127.0.0.1:9080/apisix/admin/plugins/reload -X PUT
```
