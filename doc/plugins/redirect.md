[中文](redirect-cn.md)

# redirect

URI redirect.

### Parameters

|Name    |Required|Description|
|------- |-----|------|
|uri     |required| New uri which can contain Ningx variable, eg: `/test/index.html`, `$uri/index.html`. You can refer to variables in a way similar to `${xxx}` to avoid ambiguity, eg: `${uri}foo/index.html`. If you just need the original `$` character, add `\` in front of it, like this one: `/\$foo/index.html`. If you refer to a variable name that does not exist, this will not produce an error, and it will be used as an empty string.|
|ret_code|option|Response code, the default value is `302`.|

### Example

#### Enable Plugin

Here's a mini example, enable the `redirect` plugin on the specified route:

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -X PUT -d '
{
    "uri": "/test/index.html",
    "plugins": {
        "redirect": {
            "uri": "/test/default.html",
            "ret_code": 301
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

And we can use any Nginx built-in variable in the new URI.

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -X PUT -d '
{
    "uri": "/test",
    "plugins": {
        "redirect": {
            "uri": "$uri/index.html",
            "ret_code": 301
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

#### Test Plugin

Testing based on the above examples :

```shell
$ curl http://127.0.0.1:9080/test/index.html -i
HTTP/1.1 301 Moved Permanently
Date: Wed, 23 Oct 2019 13:48:23 GMT
Content-Type: text/html
Content-Length: 166
Connection: keep-alive
Location: /test/default.html

...
```

We can check the response code and the response header `Location`.

It shows that the `redirect` plugin is in effect.

#### Disable Plugin

When you want to disable the `redirect` plugin, it is very simple,
 you can delete the corresponding json configuration in the plugin configuration,
  no need to restart the service, it will take effect immediately :

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -X PUT -d '
{
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

The `redirect` plugin has been disabled now. It works for other plugins.
