---
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
title: hmac-auth
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

## Name

`hmac-auth` is a plugin that uses HMAC (Hash-based Message Authentication Code) to authenticate requests.

## Attributes

| Name                | Type    | Required | Default | Description                                                                                                                  |
|---------------------|---------|----------|---------|------------------------------------------------------------------------------------------------------------------------------|
| access_key          | string  | True     |         | Different `access_key` can be set for different consumers.                                                                   |
| secret_key          | string  | True     |         | The value can be encrypted using the `key` in the `consumer_config`.                                                         |
| clock_skew          | integer | False    | 300     | The allowed clock skew in seconds between the client and server.                                                              |
| signed_headers      | array   | False    |         | The list of HTTP headers that must be included in the signature. If not specified, only `Date` and `@request-target` are signed. |
| validate_request_body | boolean | False    | false   | When set to `true`, validates the request body by requiring a `Digest` header and checking it against the actual body.        |

**NOTE**: `signed_headers` configuration takes precedence only when the client does not provide the `headers` field in the `Authorization` header. If the client explicitly provides `headers`, those are used instead.

## How to enable

Here's an example to enable the plugin for a specific route:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/hello",
    "plugins": {
        "hmac-auth": {}
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:8080": 1
        }
    }
}'
```

## How to set up a consumer

You need to associate the `hmac-auth` plugin with a consumer and set the `access_key` and `secret_key`:

```shell
curl http://127.0.0.1:9180/apisix/admin/consumers -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "username": "consumer_jack",
    "plugins": {
        "hmac-auth": {
            "access_key": "user-key",
            "secret_key": "secret-key"
        }
    }
}'
```

## How to generate the signature

APISIX requires the client to include the `Authorization` header in the request. The format of the `Authorization` header is:

```
Authorization: hmac-auth-v1# + access_key + + signature + + headers + signed_headers_list
```

- `hmac-auth-v1`: the signature method (fixed).
- `access_key`: the access key of the consumer.
- `signature`: the HMAC-SHA256 signature.
- `headers`: (optional) the list of HTTP headers that are included in the signature. If not provided, only `Date` and `@request-target` are signed.
- `signed_headers_list`: (optional) the list of signed headers, in lowercase, separated by spaces.

### Example

The client wants to send a `GET` request to `http://127.0.0.1:9080/hello` with a body. The consumer's `access_key` is `user-key` and `secret_key` is `secret-key`.

The steps to generate the signature are:

1. Build the signing string.

   The signing string is composed of the following lines (each line ends with `\n`):

   ```
   {key_id}\n
   {request_method} {request_path}\n
   date: {gmt_time}\n
   digest: SHA-256={base64_body_digest}\n
   ```

   - `key_id`: the access key (here it is `user-key`).
   - `request_method`: the HTTP method (e.g., `GET`).
   - `request_path`: the request URI path (e.g., `/hello`).
   - `gmt_time`: the GMT time string, e.g., `Mon, 08 Jan 2024 12:00:00 GMT`.
   - `base64_body_digest`: the Base64-encoded SHA-256 digest of the request body.

   Here is a Python code snippet that generates the signing string:

   ```python
   import hashlib
   import base64
   from datetime import datetime

   def generate_hmac_signature(key_id, secret_key, method, path, body, gmt_time):
       # Step 1: compute the body digest
       body_digest = base64.b64encode(hashlib.sha256(body.encode('utf-8')).digest()).decode('utf-8')
       digest_header = f"SHA-256={body_digest}"

       # Step 2: build the signing string
       signing_string = (
           f"{key_id}\n"
           f"{method} {path}\n"
           f"date: {gmt_time}\n"
           f"digest: {digest_header}\n"
       )

       # Step 3: compute HMAC-SHA256 signature
       import hmac
       signature = hmac.new(secret_key.encode('utf-8'), signing_string.encode('utf-8'), hashlib.sha256).hexdigest()

       return signature, digest_header
   ```

2. Build the `Authorization` header.

   If you want to sign the `Date` and `Digest` headers (along with `@request-target`), set the `headers` field to `headers="@request-target date digest"`.

   The `Authorization` header would be:

   ```
   Authorization: hmac-auth-v1#user-key# + signature + #headers="@request-target date digest"
   ```

3. Send the request with the required headers:

   ```
   GET /hello HTTP/1.1
   Host: 127.0.0.1:9080
   Date: Mon, 08 Jan 2024 12:00:00 GMT
   Digest: SHA-256=base64_body_digest
   Authorization: hmac-auth-v1#user-key#signature#headers="@request-target date digest"
   ```

**Important**: When `validate_request_body` is set to `true` in the plugin configuration, APISIX will check that the `Digest` header matches the request body. If you also want the body digest to be cryptographically bound to the signature, ensure you include the `Digest` header in the signed headers list (as shown above). You can also enforce this requirement by setting the `signed_headers` configuration option on the consumer or route.

## Example with body validation

Let's enable the plugin with body validation for a route:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/hello",
    "plugins": {
        "hmac-auth": {
            "validate_request_body": true
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:8080": 1
        }
    }
}'
```

Now the client must include a `Digest` header, and the plugin will verify that the digest matches the actual request body. For a complete end-to-end integrity check, the client should also sign the `Digest` header. See the previous section for a Python example that does this.

### Client example

Assume the consumer is configured with `access_key=user-key` and `secret_key=secret-key`, and you want to send a GET request with body "hello world" to `/hello`. Generate the signature as described in the [How to generate the signature](#how-to-generate-the-signature) section, making sure to include the `Digest` header in the signed headers list (`headers="@request-target date digest"`). The final request headers would look like:

```http
GET /hello HTTP/1.1
Host: 127.0.0.1:9080
Date: Mon, 08 Jan 2024 12:00:00 GMT
Digest: SHA-256=base64_body_digest
Authorization: hmac-auth-v1#user-key#signature#headers="@request-target date digest"
```

Replace `base64_body_digest` with the actual Base64-encoded SHA-256 digest of your body, and `signature` with the HMAC-SHA256 signature of the signing string.

## Error codes

- `401`: Missing or invalid `Authorization` header.
- `403`: Invalid signature.
- `400`: Clock skew too high.
- `400`: Missing required signed header.
- `400`: Digest header does not match the request body (when `validate_request_body` is enabled).

## Common use cases

### Protecting APIs from replay attacks

By using a timestamp in the `Date` header and limiting the clock skew, you can mitigate replay attacks. The plugin validates the time difference and rejects requests that are too old.

### Ensuring body integrity

When you enable `validate_request_body`, the plugin requires a `Digest` header and checks it against the request body. For stronger security, also include the `Digest` header in the signed headers, as shown above.

## Related plugins

- `key-auth`: Simple API key authentication.
- `jwt-auth`: JWT-based authentication.
- `basic-auth`: Basic HTTP authentication.