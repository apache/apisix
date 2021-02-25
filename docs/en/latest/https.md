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

### HTTPS

`APISIX` supports to load multiple SSL certificates by TLS extension Server Name Indication (SNI).

### Single SNI

It is most common for an SSL certificate to contain only one domain. We can create an `ssl` object. Here is a simple case, creates a `ssl` object and `route` object.

* `cert`: PEM-encoded public certificate of the SSL key pair.
* `key`: PEM-encoded private key of the SSL key pair.
* `snis`: Hostname(s) to associate with this certificate as SNIs. To set this attribute this certificate must have a valid private key associated with it.

We will use the Python script below to simplify the example:

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
# create SSL object
./ssl.py t.crt t.key test.com

# create Router object
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

Here is an example, note that the value we pass as `sni` is `*.test.com`.

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
and `mail.test.com`, then you can add them into the `snis` array. For example:

```json
{
    "snis": ["www.test.com", "mail.test.com"]
}
```

### multiple certificates for a single domain

If you want to configure multiple certificate for a single domain, for
instance, supporting both the
[ECC](https://en.wikipedia.org/wiki/Elliptic-curve_cryptography)
and RSA key-exchange algorithm, then just configure the extra certificates (the
first certificate and private key should be still put in `cert` and `key`) and
private keys by `certs` and `keys`.

* `certs`: PEM-encoded certificate array.
* `keys`: PEM-encoded private key array.

`APISIX` will pair certificate and private key with the same indice as a SSL key
pair. So the length of `certs` and `keys` must be same.
