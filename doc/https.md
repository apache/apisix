### HTTPS

`APISIX` supports to load a specific SSL certificate by TLS extension Server Name Indication (SNI).

### Single SNI

It is most common for an SSL certificate to contain only one domain. We can create an `ssl` object. Here is a simple case, creates a `ssl` object and `route` object.

* `cert`: PEM-encoded public certificate of the SSL key pair.
* `key`: PEM-encoded private key of the SSL key pair.
* `sni`: Hostname to associate with this certificate as SNIs. To set this attribute this certificate must have a valid private key associated with it.

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

Makes a test now:

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

### wildcard SNI

Sometimes, one SSL certificate may contain a wildcard domain like `*.test.com`,
that means it can accept more than one domain, eg: `www.test.com` or `mail.test.com`.

Here is an example, please pay attention on the field `sni`.


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

Makes a test:

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

### multiple domain

If your SSL certificate may contain more than one domain, like `www.test.com` and `mail.test.com`, then you can more ssl object for each domain, that is a most simple way.
