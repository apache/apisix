[English](jwt-auth.md)

# 目录
- [**名字**](#名字)
- [**属性**](#属性)
- [**如何启用**](#如何启用)
- [**测试插件**](#测试插件)
- [**禁用插件**](#禁用插件)


## 名字

`jwt-auth` 是一个认证插件，它需要与 `consumer` 一起配合才能工作。

添加 JWT Authentication 到一个 `service` 或 `route`。 然后，`consumer` 将其密钥添加到查询字符串参数、请求头或 `cookie` 中以验证其请求。

有关 JWT 的更多信息，可移步 [JWT](https://jwt.io/) 查看更多信息。

## 属性

* `key`: 不同的 `consumer` 对象应有不同的值，它应当是唯一的。不同 consumer 使用了相同的 `key` ，将会出现请求匹配异常。
* `secret`: 可选字段，加密秘钥。如果您未指定，后台将会自动帮您生成。
* `algorithm`：可选字段，加密算法。目前支持 `HS256`, `HS384`, `HS512`, `RS256` 和 `ES256`，如果未指定，则默认使用 `HS256`。
* `exp`: 可选字段，token 的超时时间，以秒为单位的计时。比如有效期是 5 分钟，那么就应设置为 `5 * 60 = 300`。

## 如何启用

1. 创建一个 consumer 对象，并设置插件 `jwt-auth` 的值。

```shell
curl http://127.0.0.1:9080/apisix/admin/consumers -X PUT -d '
{
    "username": "jack",
    "plugins": {
        "jwt-auth": {
            "key": "user-key",
            "secret": "secret-key"
        }
    }
}'
```

2. 创建 route 或 service 对象，并开启 `jwt-auth` 插件。

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/index.html",
    "plugins": {
        "jwt-auth": {}
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

#### 首先进行登录获取 `jwt-auth` token:

```shell
$ curl http://127.0.0.2:9080/apisix/plugin/jwt/sign?key=user-key -i
HTTP/1.1 200 OK
Date: Wed, 24 Jul 2019 10:33:31 GMT
Content-Type: text/plain
Transfer-Encoding: chunked
Connection: keep-alive
Server: APISIX web server

eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MTU2NDA1MDgxMX0.Us8zh_4VjJXF-TmR5f8cif8mBU7SuefPlpxhH0jbPVI
```

#### 使用获取到的 token 进行请求尝试

* 缺少 token

```shell
$ curl http://127.0.0.2:9080/index.html -i
HTTP/1.1 401 Unauthorized
...
{"message":"Missing JWT token in request"}
```

* token 放到请求头中：

```shell
$ curl http://127.0.0.2:9080/index.html -H 'Authorization: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MTU2NDA1MDgxMX0.Us8zh_4VjJXF-TmR5f8cif8mBU7SuefPlpxhH0jbPVI' -i
HTTP/1.1 200 OK
Content-Type: text/html
Content-Length: 13175
...
Accept-Ranges: bytes

<!DOCTYPE html>
<html lang="cn">
...
```

* token 放到请求参数中：

```shell
$ curl http://127.0.0.2:9080/index.html?jwt=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MTU2NDA1MDgxMX0.Us8zh_4VjJXF-TmR5f8cif8mBU7SuefPlpxhH0jbPVI -i
HTTP/1.1 200 OK
Content-Type: text/html
Content-Length: 13175
...
Accept-Ranges: bytes

<!DOCTYPE html>
<html lang="cn">
...
```

* token 放到 cookie 中：

```shell
$ curl http://127.0.0.2:9080/index.html --cookie jwt=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MTU2NDA1MDgxMX0.Us8zh_4VjJXF-TmR5f8cif8mBU7SuefPlpxhH0jbPVI -i
HTTP/1.1 200 OK
Content-Type: text/html
Content-Length: 13175
...
Accept-Ranges: bytes

<!DOCTYPE html>
<html lang="cn">
...
```

## 禁用插件

当你想去掉 `jwt-auth` 插件的时候，很简单，在插件的配置中把对应的 `json` 配置删除即可，无须重启服务，即刻生效：

```shell
$ curl http://127.0.0.1:2379/v2/keys/apisix/routes/1 -X PUT -d value='
{
    "methods": ["GET"],
    "uri": "/index.html",
    "id": 1,
    "plugins": {
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "39.97.63.215:80": 1
        }
    }
}'
```
