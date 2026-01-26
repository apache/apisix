---
title: hmac-auth
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - HMAC Authentication
  - hmac-auth
description: The hmac-auth Plugin supports HMAC authentication to ensure request integrity, preventing modifications during transmission and enhancing API security.
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

The `hmac-auth` Plugin supports HMAC (Hash-based Message Authentication Code) authentication as a mechanism to ensure the integrity of requests, preventing them from being modified during transmissions. To use the Plugin, you would configure HMAC secret keys on [Consumers](../terminology/consumer.md) and enable the Plugin on Routes or Services.

When a Consumer is successfully authenticated, APISIX adds additional headers, such as `X-Consumer-Username`, `X-Credential-Indentifier`, and other Consumer custom headers if configured, to the request, before proxying it to the Upstream service. The Upstream service will be able to differentiate between consumers and implement additional logics as needed. If any of these values is not available, the corresponding header will not be added.

Once enabled, the Plugin verifies the HMAC signature in the request's `Authorization` header and check that incoming requests are from trusted sources. Specifically, when APISIX receives an HMAC-signed request, the key ID is extracted from the `Authorization` header. APISIX then retrieves the corresponding Consumer configuration, including the secret key. If the key ID is valid and exists, APISIX generates an HMAC signature using the request's `Date` header and the secret key. If this generated signature matches the signature provided in the `Authorization` header, the request is authenticated and forwarded to Upstream services.

The Plugin implementation is based on [draft-cavage-http-signatures](https://www.ietf.org/archive/id/draft-cavage-http-signatures-12.txt).

## Attributes

The following attributes are available for configurations on Consumers or Credentials.

| Name                  | Type          | Required | Default       | Valid values                                | Description                                                                                                                                                                                               |
|-----------------------|---------------|----------|---------------|---------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| key_id            | string        | True     |               |                                             | Unique identifier for the Consumer, which identifies the associated configurations such as the secret key.                                                                                              |
| secret_key            | string        | True     |               |                                             | Secret key used to generate an HMAC. This field supports saving the value in Secret Manager using the [APISIX Secret](../terminology/secret.md) resource.                                             |

The following attributes are available for configurations on Routes or Services.

| Name                  | Type          | Required | Default       | Valid values                                | Description                                                                                                                                                                                               |
|-----------------------|---------------|----------|---------------|---------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| allowed_algorithms             | array[string]        | False    | ["hmac-sha1","hmac-sha256","hmac-sha512"] | combination of "hmac-sha1","hmac-sha256",and "hmac-sha512" | The list of HMAC algorithms allowed.                                                                                                                                                                                |
| clock_skew            | integer       | False    | 300             |                 >=1                          | Maximum allowable time difference in seconds between the client request's timestamp and APISIX server's current time. This helps account for discrepancies in time synchronization between the client’s and server’s clocks and protect against replay attacks. The timestamp in the Date header (must be in GMT format) will be used for the calculation.        |
| signed_headers        | array[string] | False    |               |                                             | The list of HMAC-signed headers that should be included in the client request's HMAC signature.  |
| validate_request_body | boolean       | False    | false         |                              | If true, validate the integrity of the request body to ensure it has not been tampered with during transmission. Specifically, the Plugin creates a SHA-256 base64-encoded digest and compare it to the `Digest` header. If the `Digest` header is missing or if the digests do not match, the validation fails.                          |
| hide_credentials | boolean       | False    | false         |                              | If true, do not pass the authorization request header to Upstream services.                        |
| anonymous_consumer | string    | False    |          |                              | Anonymous Consumer name. If configured, allow anonymous users to bypass the authentication.                        |
| realm              | string    | False    | hmac     |                              | The realm to include in the `WWW-Authenticate` header when authentication fails.                                                                                             |

NOTE: `encrypt_fields = {"secret_key"}` is also defined in the schema, which means that the field will be stored encrypted in etcd. See [encrypted storage fields](../plugin-develop.md#encrypted-storage-fields).

## Examples

The examples below demonstrate how you can work with the `hmac-auth` Plugin for different scenarios.

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Implement HMAC Authentication on a Route

The following example demonstrates how to implement HMAC authentications on a route. You will also attach a Consumer custom ID to authenticated request in the `Consumer-Custom-Id` header, which can be used to implement additional logics as needed.

Create a Consumer `john` with a custom ID label:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "john",
    "labels": {
      "custom_id": "495aec6a"
    }
  }'
```

Create `hmac-auth` Credential for the Consumer:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/john/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-john-hmac-auth",
    "plugins": {
      "hmac-auth": {
        "key_id": "john-key",
        "secret_key": "john-secret-key"
      }
    }
  }'
```

Create a Route with the `hmac-auth` Plugin using its default configurations:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "hmac-auth-route",
    "uri": "/get",
    "methods": ["GET"],
    "plugins": {
      "hmac-auth": {}
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```

Generate a signature. You can use the below Python snippet or other stack of your choice:

```python title="hmac-sig-header-gen.py"
import hmac
import hashlib
import base64
from datetime import datetime, timezone

key_id = "john-key"                # key id
secret_key = b"john-secret-key"    # secret key
request_method = "GET"             # HTTP method
request_path = "/get"              # Route URI
algorithm= "hmac-sha256"           # can use other algorithms in allowed_algorithms

# get current datetime in GMT
# note: the signature will become invalid after the clock skew (default 300s)
# you can regenerate the signature after it becomes invalid, or increase the clock
# skew to prolong the validity within the advised security boundary
gmt_time = datetime.now(timezone.utc).strftime('%a, %d %b %Y %H:%M:%S GMT')

# construct the signing string (ordered)
# the date and any subsequent custom headers should be lowercased and separated by a
# single space character, i.e. `<key>:<space><value>`
# https://datatracker.ietf.org/doc/html/draft-cavage-http-signatures-12#section-2.1.6
signing_string = (
  f"{key_id}\n"
  f"{request_method} {request_path}\n"
  f"date: {gmt_time}\n"
)

# create signature
signature = hmac.new(secret_key, signing_string.encode('utf-8'), hashlib.sha256).digest()
signature_base64 = base64.b64encode(signature).decode('utf-8')

# construct the request headers
headers = {
  "Date": gmt_time,
  "Authorization": (
    f'Signature keyId="{key_id}",algorithm="{algorithm}",'
    f'headers="@request-target date",'
    f'signature="{signature_base64}"'
  )
}

# print headers
print(headers)
```

Run the script:

```shell
python3 hmac-sig-header-gen.py
```

You should see the request headers printed:

```text
{'Date': 'Fri, 06 Sep 2024 06:41:29 GMT', 'Authorization': 'Signature keyId="john-key",algorithm="hmac-sha256",headers="@request-target date",signature="wWfKQvPDr0wHQ4IHdluB4IzeNZcj0bGJs2wvoCOT5rM="'}
```

Using the headers generated, send a request to the route:

```shell
curl -X GET "http://127.0.0.1:9080/get" \
  -H "Date: Fri, 06 Sep 2024 06:41:29 GMT" \
  -H 'Authorization: Signature keyId="john-key",algorithm="hmac-sha256",headers="@request-target date",signature="wWfKQvPDr0wHQ4IHdluB4IzeNZcj0bGJs2wvoCOT5rM="'
```

You should see an `HTTP/1.1 200 OK` response similar to the following:

```json
{
  "args": {},
  "headers": {
    "Accept": "*/*",
    "Authorization": "Signature keyId=\"john-key\",algorithm=\"hmac-sha256\",headers=\"@request-target date\",signature=\"wWfKQvPDr0wHQ4IHdluB4IzeNZcj0bGJs2wvoCOT5rM=\"",
    "Date": "Fri, 06 Sep 2024 06:41:29 GMT",
    "Host": "127.0.0.1",
    "User-Agent": "curl/8.6.0",
    "X-Amzn-Trace-Id": "Root=1-66d96513-2e52d4f35c9b6a2772d667ea",
    "X-Consumer-Username": "john",
    "X-Credential-Identifier": "cred-john-hmac-auth",
    "X-Consumer-Custom-Id": "495aec6a",
    "X-Forwarded-Host": "127.0.0.1"
  },
  "origin": "192.168.65.1, 34.0.34.160",
  "url": "http://127.0.0.1/get"
}
```

### Hide Authorization Information From Upstream

As seen the in the [last example](#implement-hmac-authentication-on-a-route), the `Authorization` header passed to the Upstream includes the signature and all other details. This could potentially introduce security risks.

The following example demonstrates how to prevent these information from being sent to the Upstream service.

Update the Plugin configuration to set `hide_credentials` to `true`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/hmac-auth-route" -X PATCH \
-H "X-API-KEY: ${admin_key}" \
-d '{
  "plugins": {
    "hmac-auth": {
      "hide_credentials": true
    }
  }
}'
```

Send a request to the route:

```shell
curl -X GET "http://127.0.0.1:9080/get" \
  -H "Date: Fri, 06 Sep 2024 06:41:29 GMT" \
  -H 'Authorization: Signature keyId="john-key",algorithm="hmac-sha256",headers="@request-target date",signature="wWfKQvPDr0wHQ4IHdluB4IzeNZcj0bGJs2wvoCOT5rM="'
```

You should see an `HTTP/1.1 200 OK` response and notice the `Authorization` header is entirely removed:

```json
{
  "args": {},
  "headers": {
    "Accept": "*/*",
    "Host": "127.0.0.1",
    "User-Agent": "curl/8.6.0",
    "X-Amzn-Trace-Id": "Root=1-66d96513-2e52d4f35c9b6a2772d667ea",
    "X-Consumer-Username": "john",
    "X-Credential-Identifier": "cred-john-hmac-auth",
    "X-Forwarded-Host": "127.0.0.1"
  },
  "origin": "192.168.65.1, 34.0.34.160",
  "url": "http://127.0.0.1/get"
}
```

### Enable Body Validation

The following example demonstrates how to enable body validation to ensure the integrity of the request body.

Create a Consumer `john`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "john"
  }'
```

Create `hmac-auth` Credential for the Consumer:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/john/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-john-hmac-auth",
    "plugins": {
      "hmac-auth": {
        "key_id": "john-key",
        "secret_key": "john-secret-key"
      }
    }
  }'
```

Create a Route with the `hmac-auth` Plugin as such:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "hmac-auth-route",
    "uri": "/post",
    "methods": ["POST"],
    "plugins": {
      "hmac-auth": {
        "validate_request_body": true
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```

Generate a signature. You can use the below Python snippet or other stack of your choice:

```python title="hmac-sig-digest-header-gen.py"
import hmac
import hashlib
import base64
from datetime import datetime, timezone

key_id = "john-key"                 # key id
secret_key = b"john-secret-key"     # secret key
request_method = "POST"             # HTTP method
request_path = "/post"              # Route URI
algorithm= "hmac-sha256"            # can use other algorithms in allowed_algorithms
body = '{"name": "world"}'          # example request body

# get current datetime in GMT
# note: the signature will become invalid after the clock skew (default 300s).
# you can regenerate the signature after it becomes invalid, or increase the clock
# skew to prolong the validity within the advised security boundary
gmt_time = datetime.now(timezone.utc).strftime('%a, %d %b %Y %H:%M:%S GMT')

# construct the signing string (ordered)
# the date and any subsequent custom headers should be lowercased and separated by a
# single space character, i.e. `<key>:<space><value>`
# https://datatracker.ietf.org/doc/html/draft-cavage-http-signatures-12#section-2.1.6
signing_string = (
    f"{key_id}\n"
    f"{request_method} {request_path}\n"
    f"date: {gmt_time}\n"
)

# create signature
signature = hmac.new(secret_key, signing_string.encode('utf-8'), hashlib.sha256).digest()
signature_base64 = base64.b64encode(signature).decode('utf-8')

# create the SHA-256 digest of the request body and base64 encode it
body_digest = hashlib.sha256(body.encode('utf-8')).digest()
body_digest_base64 = base64.b64encode(body_digest).decode('utf-8')

# construct the request headers
headers = {
    "Date": gmt_time,
    "Digest": f"SHA-256={body_digest_base64}",
    "Authorization": (
        f'Signature keyId="{key_id}",algorithm="hmac-sha256",'
        f'headers="@request-target date",'
        f'signature="{signature_base64}"'
    )
}

# print headers
print(headers)
```

Run the script:

```shell
python3 hmac-sig-digest-header-gen.py
```

You should see the request headers printed:

```text
{'Date': 'Fri, 06 Sep 2024 09:16:16 GMT', 'Digest': 'SHA-256=78qzJuLwSpZ8HacsTdFCQJWxzPMOf8bYctRk2ySLpS8=', 'Authorization': 'Signature keyId="john-key",algorithm="hmac-sha256",headers="@request-target date",signature="rjS6NxOBKmzS8CZL05uLiAfE16hXdIpMD/L/HukOTYE="'}
```

Using the headers generated, send a request to the route:

```shell
curl "http://127.0.0.1:9080/post" -X POST \
  -H "Date: Fri, 06 Sep 2024 09:16:16 GMT" \
  -H "Digest: SHA-256=78qzJuLwSpZ8HacsTdFCQJWxzPMOf8bYctRk2ySLpS8=" \
  -H 'Authorization: Signature keyId="john-key",algorithm="hmac-sha256",headers="@request-target date",signature="rjS6NxOBKmzS8CZL05uLiAfE16hXdIpMD/L/HukOTYE="' \
  -d '{"name": "world"}'
```

You should see an `HTTP/1.1 200 OK` response similar to the following:

```json
{
  "args": {},
  "data": "",
  "files": {},
  "form": {
    "{\"name\": \"world\"}": ""
  },
  "headers": {
    "Accept": "*/*",
    "Authorization": "Signature keyId=\"john-key\",algorithm=\"hmac-sha256\",headers=\"@request-target date\",signature=\"rjS6NxOBKmzS8CZL05uLiAfE16hXdIpMD/L/HukOTYE=\"",
    "Content-Length": "17",
    "Content-Type": "application/x-www-form-urlencoded",
    "Date": "Fri, 06 Sep 2024 09:16:16 GMT",
    "Digest": "SHA-256=78qzJuLwSpZ8HacsTdFCQJWxzPMOf8bYctRk2ySLpS8=",
    "Host": "127.0.0.1",
    "User-Agent": "curl/8.6.0",
    "X-Amzn-Trace-Id": "Root=1-66d978c3-49f929ad5237da5340bbbeb4",
    "X-Consumer-Username": "john",
    "X-Credential-Identifier": "cred-john-hmac-auth",
    "X-Forwarded-Host": "127.0.0.1"
  },
  "json": null,
  "origin": "192.168.65.1, 34.0.34.160",
  "url": "http://127.0.0.1/post"
}
```

If you send a request without the digest or with an invalid digest:

```shell
curl "http://127.0.0.1:9080/post" -X POST \
  -H "Date: Fri, 06 Sep 2024 09:16:16 GMT" \
  -H "Digest: SHA-256=78qzJuLwSpZ8HacsTdFCQJWxzPMOf8bYctRk2ySLpS8=" \
  -H 'Authorization: Signature keyId="john-key",algorithm="hmac-sha256",headers="@request-target date",signature="rjS6NxOBKmzS8CZL05uLiAfE16hXdIpMD/L/HukOTYE="' \
  -d '{"name": "world"}'
```

You should see an `HTTP/1.1 401 Unauthorized` response with the following message:

```text
{"message":"client request can't be validated"}
```

### Mandate Signed Headers

The following example demonstrates how you can mandate certain headers to be signed in the request's HMAC signature.

Create a Consumer `john`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "john"
  }'
```

Create `hmac-auth` Credential for the Consumer:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/john/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-john-hmac-auth",
    "plugins": {
      "hmac-auth": {
        "key_id": "john-key",
        "secret_key": "john-secret-key"
      }
    }
  }'
```

Create a Route with the `hmac-auth` Plugin which requires three headers to be present in the HMAC signature:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "hmac-auth-route",
    "uri": "/get",
    "methods": ["GET"],
    "plugins": {
      "hmac-auth": {
        "signed_headers": ["date","x-custom-header-a","x-custom-header-b"]
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```

Generate a signature. You can use the below Python snippet or other stack of your choice:

```python title="hmac-sig-req-header-gen.py"
import hmac
import hashlib
import base64
from datetime import datetime, timezone

key_id = "john-key"                # key id
secret_key = b"john-secret-key"    # secret key
request_method = "GET"             # HTTP method
request_path = "/get"              # Route URI
algorithm= "hmac-sha256"           # can use other algorithms in allowed_algorithms
custom_header_a = "hello123"       # required custom header
custom_header_b = "world456"       # required custom header

# get current datetime in GMT
# note: the signature will become invalid after the clock skew (default 300s)
# you can regenerate the signature after it becomes invalid, or increase the clock
# skew to prolong the validity within the advised security boundary
gmt_time = datetime.now(timezone.utc).strftime('%a, %d %b %Y %H:%M:%S GMT')

# construct the signing string (ordered)
# the date and any subsequent custom headers should be lowercased and separated by a
# single space character, i.e. `<key>:<space><value>`
# https://datatracker.ietf.org/doc/html/draft-cavage-http-signatures-12#section-2.1.6
signing_string = (
    f"{key_id}\n"
    f"{request_method} {request_path}\n"
    f"date: {gmt_time}\n"
    f"x-custom-header-a: {custom_header_a}\n"
    f"x-custom-header-b: {custom_header_b}\n"
)

# create signature
signature = hmac.new(secret_key, signing_string.encode('utf-8'), hashlib.sha256).digest()
signature_base64 = base64.b64encode(signature).decode('utf-8')

# construct the request headers
headers = {
    "Date": gmt_time,
    "Authorization": (
        f'Signature keyId="{key_id}",algorithm="hmac-sha256",'
        f'headers="@request-target date x-custom-header-a x-custom-header-b",'
        f'signature="{signature_base64}"'
    ),
    "x-custom-header-a": custom_header_a,
    "x-custom-header-b": custom_header_b
}

# print headers
print(headers)
```

Run the script:

```shell
python3 hmac-sig-req-header-gen.py
```

You should see the request headers printed:

```text
{'Date': 'Fri, 06 Sep 2024 09:58:49 GMT', 'Authorization': 'Signature keyId="john-key",algorithm="hmac-sha256",headers="@request-target date x-custom-header-a x-custom-header-b",signature="MwJR8JOhhRLIyaHlJ3Snbrf5hv0XwdeeRiijvX3A3yE="', 'x-custom-header-a': 'hello123', 'x-custom-header-b': 'world456'}
```

Using the headers generated, send a request to the route:

```shell
curl -X GET "http://127.0.0.1:9080/get" \
     -H "Date: Fri, 06 Sep 2024 09:58:49 GMT" \
     -H 'Authorization: Signature keyId="john-key",algorithm="hmac-sha256",headers="@request-target date x-custom-header-a x-custom-header-b",signature="MwJR8JOhhRLIyaHlJ3Snbrf5hv0XwdeeRiijvX3A3yE="' \
     -H "x-custom-header-a: hello123" \
     -H "x-custom-header-b: world456"
```

You should see an `HTTP/1.1 200 OK` response similar to the following:

```json
{
  "args": {},
  "headers": {
    "Accept": "*/*",
    "Authorization": "Signature keyId=\"john-key\",algorithm=\"hmac-sha256\",headers=\"@request-target date x-custom-header-a x-custom-header-b\",signature=\"MwJR8JOhhRLIyaHlJ3Snbrf5hv0XwdeeRiijvX3A3yE=\"",
    "Date": "Fri, 06 Sep 2024 09:58:49 GMT",
    "Host": "127.0.0.1",
    "User-Agent": "curl/8.6.0",
    "X-Amzn-Trace-Id": "Root=1-66d98196-64a58db25ece71c077999ecd",
    "X-Consumer-Username": "john",
    "X-Credential-Identifier": "cred-john-hmac-auth",
    "X-Custom-Header-A": "hello123",
    "X-Custom-Header-B": "world456",
    "X-Forwarded-Host": "127.0.0.1"
  },
  "origin": "192.168.65.1, 103.97.2.206",
  "url": "http://127.0.0.1/get"
}
```

### Rate Limit with Anonymous Consumer

The following example demonstrates how you can configure different rate limiting policies by regular and anonymous consumers, where the anonymous Consumer does not need to authenticate and has less quotas.

Create a regular Consumer `john` and configure the `limit-count` Plugin to allow for a quota of 3 within a 30-second window:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "john",
    "plugins": {
      "limit-count": {
        "count": 3,
        "time_window": 30,
        "rejected_code": 429
      }
    }
  }'
```

Create the `hmac-auth` Credential for the Consumer `john`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/john/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-john-hmac-auth",
    "plugins": {
      "hmac-auth": {
        "key_id": "john-key",
        "secret_key": "john-secret-key"
      }
    }
  }'
```

Create an anonymous user `anonymous` and configure the `limit-count` Plugin to allow for a quota of 1 within a 30-second window:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "anonymous",
    "plugins": {
      "limit-count": {
        "count": 1,
        "time_window": 30,
        "rejected_code": 429
      }
    }
  }'
```

Create a Route and configure the `hmac-auth` Plugin to accept anonymous Consumer `anonymous` from bypassing the authentication:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "hmac-auth-route",
    "uri": "/get",
    "methods": ["GET"],
    "plugins": {
      "hmac-auth": {
        "anonymous_consumer": "anonymous"
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```

Generate a signature. You can use the below Python snippet or other stack of your choice:

```python title="hmac-sig-header-gen.py"
import hmac
import hashlib
import base64
from datetime import datetime, timezone

key_id = "john-key"                # key id
secret_key = b"john-secret-key"    # secret key
request_method = "GET"             # HTTP method
request_path = "/get"              # Route URI
algorithm= "hmac-sha256"           # can use other algorithms in allowed_algorithms

# get current datetime in GMT
# note: the signature will become invalid after the clock skew (default 300s)
# you can regenerate the signature after it becomes invalid, or increase the clock
# skew to prolong the validity within the advised security boundary
gmt_time = datetime.now(timezone.utc).strftime('%a, %d %b %Y %H:%M:%S GMT')

# construct the signing string (ordered)
# the date and any subsequent custom headers should be lowercased and separated by a
# single space character, i.e. `<key>:<space><value>`
# https://datatracker.ietf.org/doc/html/draft-cavage-http-signatures-12#section-2.1.6
signing_string = (
  f"{key_id}\n"
  f"{request_method} {request_path}\n"
  f"date: {gmt_time}\n"
)

# create signature
signature = hmac.new(secret_key, signing_string.encode('utf-8'), hashlib.sha256).digest()
signature_base64 = base64.b64encode(signature).decode('utf-8')

# construct the request headers
headers = {
  "Date": gmt_time,
  "Authorization": (
    f'Signature keyId="{key_id}",algorithm="{algorithm}",'
    f'headers="@request-target date",'
    f'signature="{signature_base64}"'
  )
}

# print headers
print(headers)
```

Run the script:

```shell
python3 hmac-sig-header-gen.py
```

You should see the request headers printed:

```text
{'Date': 'Mon, 21 Oct 2024 17:31:18 GMT', 'Authorization': 'Signature keyId="john-key",algorithm="hmac-sha256",headers="@request-target date",signature="ztFfl9w7LmCrIuPjRC/DWSF4gN6Bt8dBBz4y+u1pzt8="'}
```

To verify, send five consecutive requests with the generated headers:

```shell
resp=$(seq 5 | xargs -I{} curl "http://127.0.0.1:9080/anything" -H "Date: Mon, 21 Oct 2024 17:31:18 GMT" -H 'Authorization: Signature keyId="john-key",algorithm="hmac-sha256",headers="@request-target date",signature="ztFfl9w7LmCrIuPjRC/DWSF4gN6Bt8dBBz4y+u1pzt8="' -o /dev/null -s -w "%{http_code}\n") && \
  count_200=$(echo "$resp" | grep "200" | wc -l) && \
  count_429=$(echo "$resp" | grep "429" | wc -l) && \
  echo "200": $count_200, "429": $count_429
```

You should see the following response, showing that out of the 5 requests, 3 requests were successful (status code 200) while the others were rejected (status code 429).

```text
200:    3, 429:    2
```

Send five anonymous requests:

```shell
resp=$(seq 5 | xargs -I{} curl "http://127.0.0.1:9080/anything" -o /dev/null -s -w "%{http_code}\n") && \
  count_200=$(echo "$resp" | grep "200" | wc -l) && \
  count_429=$(echo "$resp" | grep "429" | wc -l) && \
  echo "200": $count_200, "429": $count_429
```

You should see the following response, showing that only one request was successful:

```text
200:    1, 429:    4
```
