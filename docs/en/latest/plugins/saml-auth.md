---
title: saml-auth
keywords:
  - APISIX
  - Plugin
  - SAML AUTH
  - saml-auth
description: This document contains information about the Apache APISIX saml-auth Plugin.
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

## Description

The `saml-auth` Plugin can be used to access SAML (Security Assertion Markup Language 2.0) IdP (Identity Provider)
to do authentication, from the SP (service provider) perspective.

## Attributes

| Name      | Type | Required      | Description |
| ----------- | ----------- | ----------- | ----------- |
| `sp_issuer`      | string       | True      | SP name to access IdP.       |
| `idp_uri`      | string       | True      | URI of IdP.       |
| `idp_cert`      | string       | True      | IdP Certificate, used to verify saml response.       |
| `login_callback_uri`      | string       | True      | redirect uri used to callback the SP from IdP after login.       |
| `logout_uri`      | string       | True      | logout uri to trigger logout.       |
| `logout_callback_uri`      | string       | True      | redirect uri used to callback the SP from IdP after logout.       |
| `logout_redirect_uri`      | string       | True      | redirect uri after successful logout.       |
| `sp_cert`      | string       | True      | SP Certificate, used to sign the saml request.       |
| `sp_private_key`      | string       | True      | SP private key.       |

## Enabling the Plugin

You can enable the Plugin on a specific Route as shown below:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/test_saml_auth -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/anything/*",
    "plugins": {
          "saml-auth": {
            "idp_cert": "-----BEGIN CERTIFICATE-----\nMIIClzCCAX8CBgGC7zvjWjANBgkqhkiG9w0BAQsFADAPMQ0wCwYDVQQDDAR0ZXN0\nMB4XDTIyMDgzMDE0NDkxNVoXDTMyMDgzMDE0NTA1NVowDzENMAsGA1UEAwwEdGVz\ndDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAJelXTy4j6pP++7Bq9Yp\nmkuDYoBQRhUUO/RNVNOBPitVisNEQgdpKS2CFYLENZePo0xsDrN+5IB/8MTEqo3V\ntVu2BYQtq5tS0SUEgH1TLIt6gcnOuqgmmk3+RfUM3WGaUlbEN/j1C50RepFJm03i\nAM8dWCsCTCnZQLq/T4T7wwEIIOuAfz7Zip9+8HuVTOUoC3SxwVqTNb0pVRvdg7gU\nYh0f4CnckhlZG+4AgFvyW5LXxyUWbBtIpYEJN8DZEbEg+QmjuUHT0w+Apdtr6MSM\nKT87tQMxRlIYCqjmwPB9xjW1eZ9FdTGu81WeIhvs3iwTBoH6qcBR9ZJltY/VXEhg\neGECAwEAATANBgkqhkiG9w0BAQsFAAOCAQEAhbVRy4EoJzr/B84g9V6aAobUHoEF\ntv02G2GS/3UxrcaBXMLUl/tJlgti+PwQGDzIEXP0b0LLdAh/5LZFeDFVbphXUk26\nXxj3T2ej9ZcsRbaF+yHi0iisyMNdx9gbosDYg8yx9+XWImQMe6+T6+7fjYnilWE8\n0nYUuxyf1GF20EwQ0sjcJbxuq/K/2DZfOT8eo8a5c1oJFB20rE+KEpZnhBnDTQ+s\nUXPjN0AYTCKtPiAd7D190Pk1CQUbfAUmeII9WstCJhmGqIeiSpHsa9mAa50GVT3B\nnHm5obfM+sBEmy78MnC+s9Kt/EquakxeEi+YZEVfgyORq+LwNaef5MuedA==\n-----END CERTIFICATE-----",
            "login_callback_uri": "/anything/login_callback",
            "sp_private_key": "-----BEGIN PRIVATE KEY-----\nMIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQDCzo92AOThlqsF\nfxqIyA9gHrj3493UxTlhWo15OJnNL1ARNdKL4JFH6nY9sMntkLtaMdY6BYDI2lHC\nv6a1xQSxavkS4kepTFMotj7wmfLXWEY3mFbbITbGUmTQ0yQoJ4Lrii/nQ6Esv20z\nV/mSTJzHLTdcH/lIuksZXKLPnEzue3zqGopvk4ZduvwyRzU0FzPoSYlCLqAEJcx6\nbkulQcZcqSER/0bke/m9eCDt91evDJM1yOHzYuiDZH8trhFwzE+9ms/I/8Svt+tQ\nkAB5EAzfI26VpUWB3oq4eJsoEPEC4UJBsKaZh4a1GA+wbm8ql8EgUr0EsgFZH1Hg\nGg2m97nLAgMBAAECggEBAJXT0sjadS7/97c5g8nxvMmbt32ItyOfMLusrqSuILSM\nEBO8hpvoczSRorFd2GCr8Ty0meR0ORHBwCJ9zpV821gtQzX/7UfLmSX1zUC11u1D\nSnYV56+PwxYTZtCpo+RyRyIrXR6MiFjnPfDAWAXqgKY8I5jqSotiJMJz2hC9UPoV\ni56tHYXGCjtUAJrvG8FZM46TNL67nQ3ASWb5IH4cOqkgkKAJ/rZLrrMoL/HYpePr\nn2MxlvT+TgdXebxo3rngu3pLRmLsfyV9eCLoOiP/oNAxTEA35EQQlnVfZOIEit8L\nuvBYJYfYuXlxb96nQnOLqO/PrydwpXK9h1NtDvq3K2ECgYEA/i5ebOejoXORkFGx\nDyYwkTczkh7QE328LSUVIiVGh4K1zFeYtj4mYYTeQMbzhlLAf9tGAZyZmvN52/ja\niFLnI5lObNBooIfAYe3RAzUHGYraY7R1XutdOMjlP9tqjQ55y/xij/tu9qHT4fEz\naQQPJ8D5sFbB5NgjxC8rlQ/WiLECgYEAxDNss4aMNhvL2+RTda72RMt99BS8PWEZ\n/sdzzvu2zIJYFjBlCZ3Yd3vLhA/0MQXogMIcJofu4u2edZQVFSw4aHfnHFQCr45B\n1QdDhZ8zoludEevgnLdSBzNakEJ63C8AQSkjIck4IaEmW+8G7fswpWGuVDBuHQZm\nPBBcgz84CTsCgYBi8VvSWs0IYPtNyW757azEKk/J1nK605v3mtLCKu5se4YXGBYb\nAtBf75+waYGMTRQf8RQsNnBYr+REq3ctz8+nvNqZYvsHWjCaLj/JVs//slxWqX1y\nyH3OR+1tURUF+ZeRvxoC4CYOnWnkLscLXwgjOmw3p13snfI2QQJfEP460QKBgCzD\nLsGmqMaPgOsiJIhs6nK3mnzdXjUCulOOXbWTaBkwg7hMQkD3ajOYYs42dZfZqTn3\nD0UbLj1HySc6KbUy6YusD2Y/JH25DvvzNEyADd+01xkHn68hg+1wofDXugASGRTE\ntec3aT8C7SV8WzBgZrDUoFlE01p740dA1Fp9SeORAoGBAIEa6LBIXuxb13xdOPDQ\nFLaOQvmDCZeEwy2RAIOhG/1KGv+HYoCv0mMb4UXE1d65TOOE9QZLGUXksFfPc/ya\nOP1vdjF/HN3DznxQ421GdPDYVIfp7edxZstNtGMYcR/SBwoIcvwaA5c2woMHbeju\n+rbxDQL4gIT1lqn71w/8uoIJ\n-----END PRIVATE KEY-----",
            "logout_callback_uri": "/anything/logout_callback",
            "logout_uri": "/anything/logout",
            "logout_redirect_uri": "/anything/logout_ok",
            "sp_cert": "-----BEGIN CERTIFICATE-----\nMIIDgjCCAmqgAwIBAgIUOnf+MXKVU2zfIVaPz5dl0NTwPM4wDQYJKoZIhvcNAQEN\nBQAwUTELMAkGA1UEBhMCVVMxDjAMBgNVBAgMBVRleGFzMRcwFQYDVQQKDA5sdWEt\ncmVzdHktc2FtbDEZMBcGA1UEAwwQc2VydmljZS1wcm92aWRlcjAgFw0xOTA1MDgw\nMTIyMDZaGA8yMTE4MDQxNDAxMjIwNlowUTELMAkGA1UEBhMCVVMxDjAMBgNVBAgM\nBVRleGFzMRcwFQYDVQQKDA5sdWEtcmVzdHktc2FtbDEZMBcGA1UEAwwQc2Vydmlj\nZS1wcm92aWRlcjCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAMLOj3YA\n5OGWqwV/GojID2AeuPfj3dTFOWFajXk4mc0vUBE10ovgkUfqdj2wye2Qu1ox1joF\ngMjaUcK/prXFBLFq+RLiR6lMUyi2PvCZ8tdYRjeYVtshNsZSZNDTJCgnguuKL+dD\noSy/bTNX+ZJMnMctN1wf+Ui6Sxlcos+cTO57fOoaim+Thl26/DJHNTQXM+hJiUIu\noAQlzHpuS6VBxlypIRH/RuR7+b14IO33V68MkzXI4fNi6INkfy2uEXDMT72az8j/\nxK+361CQAHkQDN8jbpWlRYHeirh4mygQ8QLhQkGwppmHhrUYD7BubyqXwSBSvQSy\nAVkfUeAaDab3ucsCAwEAAaNQME4wHQYDVR0OBBYEFPbRiK9OxGCZeNUViinNQ4P5\nZOf0MB8GA1UdIwQYMBaAFPbRiK9OxGCZeNUViinNQ4P5ZOf0MAwGA1UdEwQFMAMB\nAf8wDQYJKoZIhvcNAQENBQADggEBAD0MvA3mk+u3CBDFwPtT9tI8HPSaYXS0HZ3E\nVXe4WcU3PYFpZzK0x6qr+a7mB3tbpHYXl49V7uxcIOD2aHLvKonKRRslyTiw4UvL\nOhSSByrArUGleI0wyr1BXAJArippiIhqrTDybvPpFC45x45/KtrckeM92NOlttlQ\nyd2yW0qSd9gAnqkDu2kvjLlGh9ZYnT+yHPjUuWcxDL66P3za6gc+GhVOtsOemdYN\nAErhuxiGVNHrtq2dfSedqcxtCpavMYzyGhqzxr9Lt43fpQeXeS/7JVFoC2y9buyO\nz9HIbQ6/02HIoenDoP3xfqvAY1emixgbV4iwm3SWzG8pSTxvwuM=\n-----END CERTIFICATE-----",
            "sp_issuer": "sp",
            "idp_uri": "http://127.0.0.1:8080/realms/test/protocol/saml"
          }

    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "httpbin.org": 1
        }
    }
}'

```

## Configuration description

Once you have enabled the Plugin, a new user visiting this Route would first be processed by the `saml-auth` Plugin.
If no login session exists, the user would be redirected to the login page of `idp_uri`.

After successfully logging in from IdP, IdP will redirect this user to the `login_callback_uri` with
GET parameters SAML Assertion specified. If the assertion gets verified, the login session would be created.

This process is only done once and subsequent requests are left uninterrupted.
Once this is done, the user is redirected to the original URL they wanted to visit.

Later, the user could visit `logout_uri` to start logout process. The user would be redirected to `idp_uri` to do logout.

After successfully logging out from IdP, the user would be redirected to `logout_callback_uri` and clear the session there.

Finally, the user would be redirected to `logout_redirect_uri`.

Note that, `login_callback_uri`, `logout_callback_uri`, `logout_uri` and `logout_redirect_uri` should be
either full qualified address (e.g. `http://127.0.0.1:9080/anything/logout`),
or path only (e.g. `/logout`), but it is recommended to be path only to keep consistent.

These uris need to be captured by the route where the current APISIX is located.
For example, if the `uri` of the current route is `/api/v1/*`, `login_callback_uri` can be filled in as `/api/v1/login_callback`.

## Disable Plugin

To disable the `saml-auth` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/test_saml_auth  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/anything/*",
    "plugins": {},
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "httpbin.org:80": 1
        }
    }
}'
```
