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

[Chinese](https-cn.md)
### HTTPS

`APISIX` supports to load a specific SSL certificate by TLS extension Server Name Indication (SNI).

### Single SNI

It is most common for an SSL certificate to contain only one domain. We can create an `ssl` object. Here is a simple case, creates a `ssl` object and `route` object.

* `cert`: PEM-encoded public certificate of the SSL key pair.
* `key`: PEM-encoded private key of the SSL key pair.
* `sni`: Hostname to associate with this certificate as SNIs. To set this attribute this certificate must have a valid private key associated with it.

```shell
curl http://127.0.0.1:9080/apisix/admin/ssl/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "cert": "...",
    "key": "....",
    "sni": "test.com"
}'

# make a test

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

### wildcard SNI

Sometimes, one SSL certificate may contain a wildcard domain like `*.test.com`,
that means it can accept more than one domain, eg: `www.test.com` or `mail.test.com`.

Here is an example, please pay attention on the field `sni`.


```shell
curl http://127.0.0.1:9080/apisix/admin/ssl/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "cert": "...",
    "key": "....",
    "sni": "*.test.com"
}'

# make a test

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

### multiple domain

If your SSL certificate may contain more than one domain, like `www.test.com`
and `mail.test.com`, then you can more ssl object for each domain, that is a
most simple way.
