---
title: SSL Protocol
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

`APISIX` supports set TLS protocol and also supports dynamically specifying different TLS protocol versions for each [SNI](https://en.wikipedia.org/wiki/Server_Name_Indication).

**For security reasons, the encryption suite used by default in `APISIX` does not support TLSv1.1 and lower versions.**
**If you need to enable the TLSv1.1 protocol, please add the encryption suite supported by the TLSv1.1 protocol to the configuration item `apisix.ssl.ssl_ciphers` in `config.yaml`.**

## ssl_protocols Configuration

### Static Configuration

The `ssl_protocols` parameter in the static configuration `config.yaml` applies to the entire APISIX, but cannot be dynamically modified. It only takes effect when the matching SSL resource does not set `ssl_protocols`.

```yaml
apisix:
  ssl:
    ssl_protocols: TLSv1.2 TLSv1.3 # default TLSv1.2 TLSv1.3
```

### Dynamic Configuration

Use the `ssl_protocols` field in the `ssl` resource to dynamically specify different TLS protocol versions for each SNI.

Specify the `test.com` domain uses the TLSv1.2 and TLSv1.3:

```bash
{
    "cert": "$cert",
    "key": "$key",
    "snis": ["test.com"],
    "ssl_protocols": [
        "TLSv1.2",
        "TLSv1.3"
    ]
}
```

### Notes

- Dynamic configuration has a higher priority than static configuration. When the `ssl_protocols` configuration item in the ssl resource is not empty, the static configuration will be overridden.
- The static configuration applies to the entire APISIX and requires a reload of APISIX to take effect.
- Dynamic configuration can control the TLS protocol version of each SNI in a fine-grained manner and can be dynamically modified, which is more flexible than static configuration.

## Examples

### How to specify the TLSv1.1 protocol

While newer products utilize higher security-level TLS protocol versions, there are still legacy clients that rely on the lower-level TLSv1.1 protocol. However, enabling TLSv1.1 for new products presents potential security risks. In order to maintain the security of the API, it is crucial to have the ability to seamlessly switch between different protocol versions based on specific requirements and circumstances.
For example, consider two domain names: `test.com`, utilized by legacy clients requiring TLSv1.1 configuration, and `test2.com`, associated with new products that support TLSv1.2 and TLSv1.3 protocols.

1. `config.yaml` configuration.

```yaml
apisix:
  ssl:
    ssl_protocols: TLSv1.3
    # ssl_ciphers is for reference only
    ssl_ciphers: ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-SHA:ECDHE-ECDSA-AES256-SHA:DHE-RSA-AES256-SHA:DHE-DSS-AES256-SHA
```

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

2. Specify the TLSv1.1 protocol version for the test.com domain.

```bash
curl http://127.0.0.1:9180/apisix/admin/ssls/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
     "cert" : "'"$(cat server.crt)"'",
     "key": "'"$(cat server.key)"'",
     "snis": ["test.com"],
     "ssl_protocols": [
         "TLSv1.1"
     ]
}'
```

3. Create an SSL object for test.com without specifying the TLS protocol version, which will use the static configuration by default.

```bash
curl http://127.0.0.1:9180/apisix/admin/ssls/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
     "cert" : "'"$(cat server2.crt)"'",
     "key": "'"$(cat server2.key)"'",
     "snis": ["test2.com"]
}'
```

4. Access Verification

Failed, accessed test.com with TLSv1.3:

```shell
$ curl --tls-max 1.3 --tlsv1.3  https://test.com:9443 -v -k -I
*   Trying 127.0.0.1:9443...
* Connected to test.com (127.0.0.1) port 9443 (#0)
* ALPN, offering h2
* ALPN, offering http/1.1
* successfully set certificate verify locations:
*  CAfile: /etc/ssl/certs/ca-certificates.crt
*  CApath: /etc/ssl/certs
* TLSv1.3 (OUT), TLS handshake, Client hello (1):
* TLSv1.3 (IN), TLS alert, protocol version (582):
* error:1409442E:SSL routines:ssl3_read_bytes:tlsv1 alert protocol version
* Closing connection 0
curl: (35) error:1409442E:SSL routines:ssl3_read_bytes:tlsv1 alert protocol version
```

Successfully, accessed test.com with TLSv1.1:

```shell
$ curl --tls-max 1.1 --tlsv1.1  https://test.com:9443 -v -k -I
*   Trying 127.0.0.1:9443...
* Connected to test.com (127.0.0.1) port 9443 (#0)
* ALPN, offering h2
* ALPN, offering http/1.1
* successfully set certificate verify locations:
*  CAfile: /etc/ssl/certs/ca-certificates.crt
*  CApath: /etc/ssl/certs
* TLSv1.1 (OUT), TLS handshake, Client hello (1):
* TLSv1.1 (IN), TLS handshake, Server hello (2):
* TLSv1.1 (IN), TLS handshake, Certificate (11):
* TLSv1.1 (IN), TLS handshake, Server key exchange (12):
* TLSv1.1 (IN), TLS handshake, Server finished (14):
* TLSv1.1 (OUT), TLS handshake, Client key exchange (16):
* TLSv1.1 (OUT), TLS change cipher, Change cipher spec (1):
* TLSv1.1 (OUT), TLS handshake, Finished (20):
* TLSv1.1 (IN), TLS handshake, Finished (20):
* SSL connection using TLSv1.1 / ECDHE-RSA-AES256-SHA
```

Successfully, accessed test2.com with TLSv1.3:

```shell
$ curl --tls-max 1.3 --tlsv1.3  https://test2.com:9443 -v -k -I
*   Trying 127.0.0.1:9443...
* Connected to test2.com (127.0.0.1) port 9443 (#0)
* ALPN, offering h2
* ALPN, offering http/1.1
* successfully set certificate verify locations:
*  CAfile: /etc/ssl/certs/ca-certificates.crt
*  CApath: /etc/ssl/certs
* TLSv1.3 (OUT), TLS handshake, Client hello (1):
* TLSv1.3 (IN), TLS handshake, Server hello (2):
* TLSv1.3 (IN), TLS handshake, Encrypted Extensions (8):
* TLSv1.3 (IN), TLS handshake, Certificate (11):
* TLSv1.3 (IN), TLS handshake, CERT verify (15):
* TLSv1.3 (IN), TLS handshake, Finished (20):
* TLSv1.3 (OUT), TLS change cipher, Change cipher spec (1):
* TLSv1.3 (OUT), TLS handshake, Finished (20):
* SSL connection using TLSv1.3 / TLS_AES_256_GCM_SHA384
```

Failed, accessed test2.com with TLSv1.1:

```shell
curl --tls-max 1.1 --tlsv1.1  https://test2.com:9443 -v -k -I
*   Trying 127.0.0.1:9443...
* Connected to test2.com (127.0.0.1) port 9443 (#0)
* ALPN, offering h2
* ALPN, offering http/1.1
* successfully set certificate verify locations:
*  CAfile: /etc/ssl/certs/ca-certificates.crt
*  CApath: /etc/ssl/certs
* TLSv1.1 (OUT), TLS handshake, Client hello (1):
* TLSv1.1 (IN), TLS alert, protocol version (582):
* error:1409442E:SSL routines:ssl3_read_bytes:tlsv1 alert protocol version
* Closing connection 0
curl: (35) error:1409442E:SSL routines:ssl3_read_bytes:tlsv1 alert protocol version
```

### Certificates are associated with multiple domains, but different TLS protocols are used between domains

Sometimes, we may encounter a situation where a certificate is associated with multiple domains, but they need to use different TLS protocols to ensure security. For example, the test.com domain needs to use the TLSv1.2 protocol, while the test2.com domain needs to use the TLSv1.3 protocol. In this case, we cannot simply create an SSL object for all domains, but need to create an SSL object for each domain separately and specify the appropriate protocol version. This way, we can perform the correct SSL handshake and encrypted communication based on different domains and protocol versions. The example is as follows:

1. Create an SSL object for test.com using the certificate and specify the TLSv1.2 protocol.

```bash
curl http://127.0.0.1:9180/apisix/admin/ssls/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
     "cert" : "'"$(cat server.crt)"'",
     "key": "'"$(cat server.key)"'",
     "snis": ["test.com"],
     "ssl_protocols": [
         "TLSv1.2"
     ]
}'
```

2. Use the same certificate as test.com to create an SSL object for test2.com and specify the TLSv1.3 protocol.

```bash
curl http://127.0.0.1:9180/apisix/admin/ssls/2 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
     "cert" : "'"$(cat server.crt)"'",
     "key": "'"$(cat server.key)"'",
     "snis": ["test2.com"],
     "ssl_protocols": [
         "TLSv1.3"
     ]
}'
```

3. Access verification

Successfully, accessed test.com with TLSv1.2:

```shell
$ curl --tls-max 1.2 --tlsv1.2  https://test.com:9443 -v -k -I
*   Trying 127.0.0.1:9443...
* Connected to test.com (127.0.0.1) port 9443 (#0)
* ALPN, offering h2
* ALPN, offering http/1.1
* successfully set certificate verify locations:
*  CAfile: /etc/ssl/certs/ca-certificates.crt
*  CApath: /etc/ssl/certs
* TLSv1.2 (OUT), TLS handshake, Client hello (1):
* TLSv1.2 (IN), TLS handshake, Server hello (2):
* TLSv1.2 (IN), TLS handshake, Certificate (11):
* TLSv1.2 (IN), TLS handshake, Server key exchange (12):
* TLSv1.2 (IN), TLS handshake, Server finished (14):
* TLSv1.2 (OUT), TLS handshake, Client key exchange (16):
* TLSv1.2 (OUT), TLS change cipher, Change cipher spec (1):
* TLSv1.2 (OUT), TLS handshake, Finished (20):
* TLSv1.2 (IN), TLS handshake, Finished (20):
* SSL connection using TLSv1.2 / ECDHE-RSA-AES128-GCM-SHA256
* ALPN, server accepted to use h2
* Server certificate:
*  subject: C=AU; ST=Some-State; O=Internet Widgits Pty Ltd; CN=test.com
*  start date: Jul 20 15:50:08 2023 GMT
*  expire date: Jul 17 15:50:08 2033 GMT
*  issuer: C=AU; ST=Some-State; O=Internet Widgits Pty Ltd; CN=test.com
*  SSL certificate verify result: EE certificate key too weak (66), continuing anyway.
* Using HTTP2, server supports multi-use
* Connection state changed (HTTP/2 confirmed)
* Copying HTTP/2 data in stream buffer to connection buffer after upgrade: len=0
* Using Stream ID: 1 (easy handle 0x5608905ee2e0)
> HEAD / HTTP/2
> Host: test.com:9443
> user-agent: curl/7.74.0
> accept: */*

```

Failed, accessed test.com with TLSv1.3:

```shell
$ curl --tls-max 1.3 --tlsv1.3  https://test.com:9443 -v -k -I
*   Trying 127.0.0.1:9443...
* Connected to test.com (127.0.0.1) port 9443 (#0)
* ALPN, offering h2
* ALPN, offering http/1.1
* successfully set certificate verify locations:
*  CAfile: /etc/ssl/certs/ca-certificates.crt
*  CApath: /etc/ssl/certs
* TLSv1.3 (OUT), TLS handshake, Client hello (1):
* TLSv1.3 (IN), TLS alert, protocol version (582):
* error:1409442E:SSL routines:ssl3_read_bytes:tlsv1 alert protocol version
* Closing connection 0
curl: (35) error:1409442E:SSL routines:ssl3_read_bytes:tlsv1 alert protocol version

```

Successfully, accessed test2.com with TLSv1.3:

```shell
$ curl --tls-max 1.3 --tlsv1.3  https://test2.com:9443 -v -k -I
*   Trying 127.0.0.1:9443...
* Connected to test2.com (127.0.0.1) port 9443 (#0)
* ALPN, offering h2
* ALPN, offering http/1.1
* successfully set certificate verify locations:
*  CAfile: /etc/ssl/certs/ca-certificates.crt
*  CApath: /etc/ssl/certs
* TLSv1.3 (OUT), TLS handshake, Client hello (1):
* TLSv1.3 (IN), TLS handshake, Server hello (2):
* TLSv1.3 (IN), TLS handshake, Encrypted Extensions (8):
* TLSv1.3 (IN), TLS handshake, Certificate (11):
* TLSv1.3 (IN), TLS handshake, CERT verify (15):
* TLSv1.3 (IN), TLS handshake, Finished (20):
* TLSv1.3 (OUT), TLS change cipher, Change cipher spec (1):
* TLSv1.3 (OUT), TLS handshake, Finished (20):
* SSL connection using TLSv1.3 / TLS_AES_256_GCM_SHA384
* ALPN, server accepted to use h2
* Server certificate:
*  subject: C=AU; ST=Some-State; O=Internet Widgits Pty Ltd; CN=test2.com
*  start date: Jul 20 16:05:47 2023 GMT
*  expire date: Jul 17 16:05:47 2033 GMT
*  issuer: C=AU; ST=Some-State; O=Internet Widgits Pty Ltd; CN=test2.com
*  SSL certificate verify result: EE certificate key too weak (66), continuing anyway.
* Using HTTP2, server supports multi-use
* Connection state changed (HTTP/2 confirmed)
* Copying HTTP/2 data in stream buffer to connection buffer after upgrade: len=0
* Using Stream ID: 1 (easy handle 0x55569cbe42e0)
> HEAD / HTTP/2
> Host: test2.com:9443
> user-agent: curl/7.74.0
> accept: */*
>
* TLSv1.3 (IN), TLS handshake, Newsession Ticket (4):
* TLSv1.3 (IN), TLS handshake, Newsession Ticket (4):
* old SSL session ID is stale, removing
```

Failed, accessed test2.com with TLSv1.2:

```shell
$ curl --tls-max 1.2 --tlsv1.2  https://test2.com:9443 -v -k -I
*   Trying 127.0.0.1:9443...
* Connected to test2.com (127.0.0.1) port 9443 (#0)
* ALPN, offering h2
* ALPN, offering http/1.1
* successfully set certificate verify locations:
*  CAfile: /etc/ssl/certs/ca-certificates.crt
*  CApath: /etc/ssl/certs
* TLSv1.2 (OUT), TLS handshake, Client hello (1):
* TLSv1.2 (IN), TLS alert, protocol version (582):
* error:1409442E:SSL routines:ssl3_read_bytes:tlsv1 alert protocol version
* Closing connection 0
curl: (35) error:1409442E:SSL routines:ssl3_read_bytes:tlsv1 alert protocol version
```
