### HTTPS

`APISIX` 支持通过 TLS 扩展 SNI 实现加载特定的 SSL 证书以实现对 https 的支持。

SNI(Server Name Indication)是用来改善 SSL 和 TLS 的一项特性，
它允许客户端在服务器端向其发送证书之前请求服务器的域名。

### 单一域名指定

通常情况下一个 SSL 证书只指定一个域名，我们可以配置一个 `ssl` 参数对象，他包括 cret、key、sni 三个属性，详细如下

* `cert`: SSL 密钥对的公钥，pem 格式
* `key`: SSL 密钥对的私钥，pem 格式
* `sni`: SSL 证书所指定的域名，注意在设置这个参数之前，你需要确保这个证书对应的私钥是有效的。

```shell
curl http://127.0.0.1:9080/apisix/admin/ssl/1 -X PUT -d '
{
    "cert": "...",
    "key": "....",
    "sni": "test.com"
}'

curl http://127.0.0.1:9080/apisix/admin/routes/1 -X PUT -d '
{
    "uri": "/index.html",
    "plugins": {
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

测试下:

```shell
$ curl -i http://127.0.0.1:9443/index.html
HTTP/1.1 200 OK
Content-Type: text/html
Content-Length: 13175
Connection: keep-alive
X-RateLimit-Limit: 2
X-RateLimit-Remaining: 1
Server: APISIX web server
Date: Mon, 03 Jun 2019 09:38:32 GMT
Last-Modified: Wed, 24 Apr 2019 00:14:17 GMT
ETag: "5cbfaa59-3377"
Accept-Ranges: bytes

...
```

### 通配符域名指定

有时候，一个 SSL 证书可能也需要指定特定的一群域名，如`*.test.com`,
也就是意味着SNI可以支持基于通配符的多域名支撑。
像刚才这个配置，就可以支持 `www.test.com` 或者 `mail.test.com`

看下面这个例子，请注意 sni 这个属性

```shell
curl http://127.0.0.1:9080/apisix/admin/ssl/1 -X PUT -d '
{
    "cert": "...",
    "key": "....",
    "sni": "*.test.com"
}'

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -X PUT -d '
{
    "uri": "/index.html",
    "plugins": {
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

测试下:

```shell
$ curl -i http://127.0.0.1:9443/index.html
HTTP/1.1 200 OK
Content-Type: text/html
Content-Length: 13175
Connection: keep-alive
X-RateLimit-Limit: 2
X-RateLimit-Remaining: 1
Server: APISIX web server
Date: Mon, 03 Jun 2019 09:38:32 GMT
Last-Modified: Wed, 24 Apr 2019 00:14:17 GMT
ETag: "5cbfaa59-3377"
Accept-Ranges: bytes

...
```

### 多域名的情况

如果你的 SSL 证书需要指定多个域名，又无法通过通配符来实现，
那么你就只能针对每个域名，都单独设置对应的证书。
