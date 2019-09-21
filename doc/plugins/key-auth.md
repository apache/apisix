[中文](key-auth-cn.md)

# Summary
- [**Name**](#name)
- [**Attributes**](#attributes)
- [**How To Enable**](#how-to-enable)
- [**Test Plugin**](#test-plugin)
- [**Disable Plugin**](#disable-plugin)


## Name

`key-auth` is an authentication plugin, it should work with `consumer` together.

Add Key Authentication (also sometimes referred to as an API key) to a Service or a Route. Consumers then add their key either in a querystring parameter or a header to authenticate their requests.

## Attributes

* `key`: different consumer objects should use different values, it should be unique.

## How To Enable

Two steps are required:

1. creates a consumer object, and set the attributes of plugin `key-auth`.

```shell
curl http://127.0.0.1:9080/apisix/admin/consumers -X PUT -d '
{
    "username": "jack",
    "plugins": {
        "key-auth": {
            "key": "auth-one"
        }
    }
}'
```

2. creates a route or service object, and enable plugin `key-auth`.

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/index.html",
    "id": 1,
    "plugins": {
        "key-auth": {}
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "39.97.63.215:80": 1
        }
    }
}'
```

## Test Plugin

Here is a correct test example:

```shell
$ curl http://127.0.0.2:9080/index.html -H 'apikey: keykey' -i
HTTP/1.1 200 OK
...
```

If the request does not set `apikey` correctly, will get a `401` response.

```shell
$ curl http://127.0.0.2:9080/index.html -i
HTTP/1.1 401 Unauthorized
...
{"message":"Missing API key found in request"}

$ curl http://127.0.0.2:9080/index.html -H 'apikey: abcabcabc' -i
HTTP/1.1 401 Unauthorized
...
{"message":"Invalid API key in request"}
```

## Disable Plugin

When you want to disable the `key-auth` plugin, it is very simple,
 you can delete the corresponding json configuration in the plugin configuration,
  no need to restart the service, it will take effect immediately:

```shell
$ curl http://127.0.0.1:2379/v2/keys/apisix/routes/1 -X PUT -d value='
{
    "uri": "/index.html",
    "plugins": {},
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "39.97.63.215:80": 1
        }
    }
}'
```

The `key-auth` plugin has been disabled now. It works for other plugins.
