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

# HMAC Generate Signature Examples

## Python 3

```python
import hashlib
import hmac
import base64

secret = bytes('the shared secret key here', 'utf-8')
message = bytes('this is signature string', 'utf-8')


hash = hmac.new(secret, message, hashlib.sha256)

# to lowercase hexits
hash.hexdigest()

# to lowercase base64
base64.b64encode(hash.digest())
```

## Java

```java
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.security.NoSuchAlgorithmException;
import java.security.InvalidKeyException;
import javax.xml.bind.DatatypeConverter;

class Main {
  public static void main(String[] args) {
   try {
     String secret = "the shared secret key here";
     String message = "this is signature string";

     Mac hasher = Mac.getInstance("HmacSHA256");
     hasher.init(new SecretKeySpec(secret.getBytes(), "HmacSHA256"));

     byte[] hash = hasher.doFinal(message.getBytes());

     // to lowercase hexits
     DatatypeConverter.printHexBinary(hash);

     // to base64
     DatatypeConverter.printBase64Binary(hash);
   }
   catch (NoSuchAlgorithmException e) {}
   catch (InvalidKeyException e) {}
  }
}
```

## Go

```go
package main

import (
    "crypto/hmac"
    "crypto/sha256"
    "encoding/base64"
    "encoding/hex"
)

func main() {
    secret := []byte("the shared secret key here")
    message := []byte("this is signature string")

    hash := hmac.New(sha256.New, secret)
    hash.Write(message)

    // to lowercase hexits
    hex.EncodeToString(hash.Sum(nil))

    // to base64
    base64.StdEncoding.EncodeToString(hash.Sum(nil))
}
```

## Ruby

```ruby
require 'openssl'
require 'base64'

secret = 'the shared secret key here'
message = 'this is signature string'

# to lowercase hexits
OpenSSL::HMAC.hexdigest('sha256', secret, message)

# to base64
Base64.encode64(OpenSSL::HMAC.digest('sha256', secret, message))
```

## NodeJs

```js
var crypto = require('crypto');

var secret = 'the shared secret key here';
var message = 'this is signature string';

var hash = crypto.createHmac('sha256', secret).update(message);

// to lowercase hexits
hash.digest('hex');

// to base64
hash.digest('base64');
```

## JavaScript ES6

```js
const secret = 'the shared secret key here';
const message = 'this is signature string';

const getUtf8Bytes = str =>
  new Uint8Array(
    [...unescape(encodeURIComponent(str))].map(c => c.charCodeAt(0))
  );

const secretBytes = getUtf8Bytes(secret);
const messageBytes = getUtf8Bytes(message);

const cryptoKey = await crypto.subtle.importKey(
  'raw', secretBytes, { name: 'HMAC', hash: 'SHA-256' },
  true, ['sign']
);
const sig = await crypto.subtle.sign('HMAC', cryptoKey, messageBytes);

// to lowercase hexits
[...new Uint8Array(sig)].map(b => b.toString(16).padStart(2, '0')).join('');

// to base64
btoa(String.fromCharCode(...new Uint8Array(sig)));
```

## PHP

```php
<?php

$secret = 'the shared secret key here';
$message = 'this is signature string';

// to lowercase hexits
hash_hmac('sha256', $message, $secret);

// to base64
base64_encode(hash_hmac('sha256', $message, $secret, true));
```

## Lua

```lua
local hmac = require("resty.hmac")
local secret = 'the shared secret key here'
local message = 'this is signature string'
local digest = hmac:new(secret, hmac.ALGOS.SHA256):final(message)

--to lowercase hexits
ngx.say(digest)

--to base64
ngx.say(ngx.encode_base64(digest))
```

## Shell

```bash
SECRET="the shared secret key here"
MESSAGE="this is signature string"

# to lowercase hexits
echo -n $MESSAGE | openssl dgst -sha256 -hmac $SECRET

# to base64
echo -n $MESSAGE | openssl dgst -sha256 -hmac $SECRET -binary | base64
```
