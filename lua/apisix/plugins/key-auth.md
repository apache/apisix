# key-auth

Here is an example of binding to specified plugin, such as `key-auth`:

```shell
$ curl http://127.0.0.1:2379/v2/keys/plugins/key-auth/consumers\?recursive\=true | python -m json.tool
{
    "action": "get",
    "node": {
        "createdIndex": 1600,
        "dir": true,
        "key": "/plugins/key-auth/consumers",
        "modifiedIndex": 1600,
        "nodes": [
            {
                "createdIndex": 1603,
                "key": "/plugins/key-auth/consumers/ShunFeng",
                "modifiedIndex": 1603,
                "value": "{\"key\":\"dddxxyyy\",\"id\":\"ShunFeng\"}"
            }
        ]
    }
}
```
