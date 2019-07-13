### HTTPS

`APISIX` 支持通过 TLS 扩展 SNI 实现加载特定的 SSL 证书以实现对 https 的支持。

SNI(Server Name Indication)是用来改善 SSL 和 TLS 的一项特性，它允许客户端在服务器端向其发送证书之前向服务器端发送请求的域名，服务器端根据客户端请求的域名选择合适的SSL证书发送给客户端。

### 单一域名指定

通常情况下一个 SSL 证书只指定一个域名，我们可以配置一个 `ssl` 参数对象，它包括 cert、key、sni 三个属性，详细如下

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

# 测试一下

curl --resolve 'test.com:9443:127.0.0.1' https://test.com:9443/hello  -vvv
* Added test.com:9443:127.0.0.1 to DNS cache
* About to connect() to test.com port 9443 (#0)
*   Trying 127.0.0.1...
* Connected to test.com (127.0.0.1) port 9443 (#0)
* Initializing NSS with certpath: sql:/etc/pki/nssdb
* skipping SSL peer certificate verification
* SSL connection using TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384
* Server certificate:
* 	subject: CN=test.com,O=iresty,L=ZhuHai,ST=GuangDong,C=CN
* 	start date: Jun 24 22:18:05 2019 GMT
* 	expire date: May 31 22:18:05 2119 GMT
* 	common name: test.com
* 	issuer: CN=test.com,O=iresty,L=ZhuHai,ST=GuangDong,C=CN
> GET /hello HTTP/1.1
> User-Agent: curl/7.29.0
> Host: test.com:9443
> Accept: */*
```

### 通配符域名指定

有时候，一个 SSL 证书也需要指定特定的一类域名，如`*.test.com`,
也就是意味着SNI可以支持基于通配符的多域名支撑。
像这个配置，就可以支持 `www.test.com` 或者 `mail.test.com`

看下面这个例子，请注意 sni 这个属性

```shell
curl http://127.0.0.1:9080/apisix/admin/ssl/1 -X PUT -d '
{
    "cert": "...",
    "key": "....",
    "sni": "*.test.com"
}'

# 测试一下

curl --resolve 'www.test.com:9443:127.0.0.1' https://www.test.com:9443/hello  -vvv
* Added test.com:9443:127.0.0.1 to DNS cache
* About to connect() to test.com port 9443 (#0)
*   Trying 127.0.0.1...
* Connected to test.com (127.0.0.1) port 9443 (#0)
* Initializing NSS with certpath: sql:/etc/pki/nssdb
* skipping SSL peer certificate verification
* SSL connection using TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384
* Server certificate:
* 	subject: CN=test.com,O=iresty,L=ZhuHai,ST=GuangDong,C=CN
* 	start date: Jun 24 22:18:05 2019 GMT
* 	expire date: May 31 22:18:05 2119 GMT
* 	common name: test.com
* 	issuer: CN=test.com,O=iresty,L=ZhuHai,ST=GuangDong,C=CN
> GET /hello HTTP/1.1
> User-Agent: curl/7.29.0
> Host: test.com:9443
> Accept: */*
```

### 多域名的情况

如果你的 SSL 证书指定了多个域名，这多个证书无法通过通配符来描述，比如`www.test.com`和`mail.test.com`， 那么你就只能针对每个域名，都单独设置同样的同样的证书。
