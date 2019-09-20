[English](https.md)
### HTTPS

`APISIX` 支持通过 TLS 扩展 SNI 实现加载特定的 SSL 证书以实现对 https 的支持。

SNI(Server Name Indication)是用来改善 SSL 和 TLS 的一项特性，它允许客户端在服务器端向其发送证书之前向服务器端发送请求的域名，服务器端根据客户端请求的域名选择合适的SSL证书发送给客户端。

### 单一域名指定

通常情况下一个 SSL 证书只包含一个静态域名，配置一个 `ssl` 参数对象，它包括 `cert`、`key`和`sni`三个属性，详细如下：

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

### 范域名

一个 SSL 证书的域名也可能包含范域名，如`*.test.com`，它代表所有以`test.com`结尾的域名都可以使用该证书。
比如`*.test.com`，可以匹配 `www.test.com`、`mail.test.com`甚至`a.b.test.com`。

看下面这个例子，请注意 `sni` 这个属性:

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

如果一个 SSL 证书包含多个独立域名，比如`www.test.com`和`mail.test.com`，通配符方式又会导致匹配不严谨。
所以针对不同域名，设置不同 SSL 证书对象即可。
