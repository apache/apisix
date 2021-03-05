---
title: HTTPS
---

<!--
#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
-->

`APISIX` 支持通过 TLS 扩展 SNI 实现加载特定的 SSL 证书以实现对 https 的支持。

SNI(Server Name Indication)是用来改善 SSL 和 TLS 的一项特性，它允许客户端在服务器端向其发送证书之前向服务器端发送请求的域名，服务器端根据客户端请求的域名选择合适的SSL证书发送给客户端。

### 单一域名指定

通常情况下一个 SSL 证书只包含一个静态域名，配置一个 `ssl` 参数对象，它包括 `cert`、`key`和`sni`三个属性，详细如下：

* `cert`: SSL 密钥对的公钥，pem 格式
* `key`: SSL 密钥对的私钥，pem 格式
* `snis`: SSL 证书所指定的一个或多个域名，注意在设置这个参数之前，你需要确保这个证书对应的私钥是有效的。

为了简化示例，我们会使用下面的 Python 脚本:

```python
#!/usr/bin/env python
# coding: utf-8
# save this file as ssl.py
import sys
# sudo pip install requests
import requests

if len(sys.argv) <= 3:
    print("bad argument")
    sys.exit(1)
with open(sys.argv[1]) as f:
    cert = f.read()
with open(sys.argv[2]) as f:
    key = f.read()
sni = sys.argv[3]
api_key = "edd1c9f034335f136f87ad84b625c8f1"
resp = requests.put("http://127.0.0.1:9080/apisix/admin/ssl/1", json={
    "cert": cert,
    "key": key,
    "snis": [sni],
}, headers={
    "X-API-KEY": api_key,
})
print(resp.status_code)
print(resp.text)
```

```shell
# 创建 SSL 对象
./ssl.py t.crt t.key test.com

# 创建 Router 对象
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -i -d '
{
    "uri": "/hello",
    "hosts": ["test.com"],
    "methods": ["GET"],
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
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

### 泛域名

一个 SSL 证书的域名也可能包含泛域名，如`*.test.com`，它代表所有以`test.com`结尾的域名都可以使用该证书。
比如`*.test.com`，可以匹配 `www.test.com`、`mail.test.com`甚至`a.b.test.com`。

看下面这个例子，请注意我们把 `*.test.com` 作为 sni 传递进来:

```shell
./ssl.py t.crt t.key '*.test.com'

curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -i -d '
{
    "uri": "/hello",
    "hosts": ["*.test.com"],
    "methods": ["GET"],
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
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

如果一个 SSL 证书包含多个独立域名，比如`www.test.com`和`mail.test.com`，
你可以把它们都放入 `snis` 数组中，就像这样：

```json
{
    "snis": ["www.test.com", "mail.test.com"]
}
```

### 单域名多证书的情况

如果你期望为一个域名配置多张证书，例如以此来同时支持使用 ECC 和 RSA
的密钥交换算法，那么你可以将额外的证书和私钥（第一张证书和其私钥依然使用 `cert` 和 `key`）配置在 `certs` 和 `keys` 中。

* `certs`：PEM 格式的 SSL 证书列表
* `keys`：PEM 格式的 SSL 证书私钥列表

`APISIX` 会将相同下标的证书和私钥配对使用，因此 `certs` 和 `keys` 列表的长度必须一致。
