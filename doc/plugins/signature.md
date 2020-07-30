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

[Chinese](../zh-cn/plugins/signature.md)

# signature

Plugin Signature definition is similar [Wechat Pay Signature Specification](https://pay.weixin.qq.com/wiki/doc/api/jsapi.php?chapter=4_3)，it's better to verify request is valid or not 
in p2p communication scenario.

## Attributes

|Name            |Requirement |Description|
|----------------|------------|-----------|
|appkey          |required    |application key|
|secret          |required    |application secret|
|algorithm       |required    |signature algorithm, only support md5 now|
|timeout         |required    |request duration timeout，default 10s|
|anti_reply      |optional    |anti reply attack, default false|
|policy          |optional    |anti_reply policies to use for retrieving request is a reply attack, only support `redis` now|
|redis_host      |optional    |when using the `redis` policy, this property specifies the address of the Redis server|
|redis_port      |optional    |when using the `redis` policy, this property specifies the port of the Redis server. The default port is 6379|
|redis_password  |optional    |when using the `redis` policy, this property specifies the password of the Redis server|
|redis_timeout   |optional    |when using the `redis` policy, this property specifies the timeout in milliseconds of any command submitted to the Redis server. The default timeout is 1000 ms(1 second).|
|redis_keepalive |optional    |when using the `redis` policy, this property specifies redis connection cached time (keepalive time). default 10s|
|redis_poolsize  |optional    |when using the `redis` policy, this property specifies the pool size of redis connections. default size 100|

## signature specification
Required Keys in Request Header:

|Name        |Requirement  |Description|
|------------|-------------|-----------|
|Appkey      |required     |application Key|
|Timestamp   |required     |request timestamp|
|Sign        |required     |sign|
|Nonce       | required    |request nonce|

Signature formula:

```
sign = md5(encode_args(ngx.req.get_uri_args()) .. (ngx.req.get_body_data() or "") .. secret .. timestamp .. nonce)
```

#### Enable Plugin

Here's an example, enable the `signature` plugin on the specified route:

```shell
curl -i http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/api/verify",
    "plugins": {
        "signature": {
        	"appkey":"your_appkey",
            "secret":"your_secret",
            "anti_reply":true,
			"timeout":10,	    
			"algorithm":"md5",
			"policy":"redis",
			"redis_timeout":1,
			"redis_password":"",
			"redis_keepalive":10,
			"redis_poolsize":100,
			"redis_port":6379,
			"redis_host":"127.0.0.1"
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "39.97.63.215:80": 1
        }
    }
}'
```

#### Test Plugin

The above configuration enable signature plugin for route: /api/verify: 

```shell
curl -X POST \
  'http://localhost:9080/api/verify?hello=world&a=b' \
  -H 'Accept: */*' \
  -H 'Appkey: IpHf8JGfJeJoniRm' \
  -H 'Cache-Control: no-cache' \
  -H 'Connection: keep-alive' \
  -H 'Content-Type: application/json' \
  -H 'Host: localhost:9080' \
  -H 'Nonce: 4782a6687075a91238eb54ab14d8a4a8' \
  -H 'Sign: 8648942398291b20cd291714a876709e' \
  -H 'Timestamp: 1594879461' \
  -H 'accept-encoding: gzip, deflate' \
  -H 'cache-control: no-cache' \
  -H 'content-length: 38' \
  -d '{
    "hello": "world",
    "age": 1
	}'
```

Response:

```
{"message":"invalid request, wrong signature"}
```

That means plugin `signature` take effect.

#### Disable Plugin

It's easy to disable plugin `signature`, just delete it's json config and it will take effect immediately.

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/api/verify",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "39.97.63.215:80": 1
        }
    }
}'
```

The `signature` plugin has been disabled now. It works for other plugins.
