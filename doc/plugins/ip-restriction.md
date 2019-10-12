[中文](ip-restriction-cn.md)

# Summary
- [**Name**](#name)
- [**Attributes**](#attributes)
- [**How To Enable**](#how-to-enable)
- [**Test Plugin**](#test-plugin)
- [**Disable Plugin**](#disable-plugin)


## Name

The `ip-restriction` can restrict access to a Service or a Route by either
whitelisting or blacklisting IP addresses. Single IPs, multiple IPs or ranges
in CIDR notation like 10.10.10.0/24 can be used(will support IPv6 soon).

## Attributes

|name     |option  |description|
|---------|--------|-----------|
|whitelist|option  |List of IPs or CIDR ranges to whitelist|
|blacklist|option  |List of IPs or CIDR ranges to blacklist|

One of `whitelist` or `blacklist` must be specified, and they can not work
together.

## How To Enable

Two steps are required:

1. creates a route or service object, and enable plugin `ip-restriction`.

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -X PUT -d '
{
    "uri": "/index.html",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    },
    "plugins": {
        "ip-restriction": {
            "whitelist": [
                "127.0.0.1",
                "113.74.26.106/24"
            ]
        }
    }
}'
```

## Test Plugin

Requests to `127.0.0.1`:

```shell
$ curl http://127.0.0.1:9080/index.html
HTTP/1.1 200 OK
...
```

Requests to `127.0.0.2`:

```shell
$ curl http://127.0.0.2:9080/index.html -i
HTTP/1.1 403 Forbidden
...
{"message":"Your IP address is not allowed"}
```

## Disable Plugin

When you want to disable the `ip-restriction` plugin, it is very simple,
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

The `ip-restriction` plugin has been disabled now. It works for other plugins.
