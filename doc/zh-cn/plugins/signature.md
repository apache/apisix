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

[English](../../plugins/signature.md)

# signature

和 [微信支付签名规范](https://pay.weixin.qq.com/wiki/doc/api/jsapi.php?chapter=4_3)类似，在端对端API调用时，通过签名校验请求的合法性。

## 参数

|名称              |可选项    |说明|
|-----------------|---------|-----------|
|appkey           |必选     |端应用的Key|
|secret           |必选     |应用密钥|
|algorithm        |必选     |签名算法，目前仅支持md5|
|timeout          |必选     |当请求到达服务器时间与请求发起时间之差超过该值时，直接拒绝请求并返回400，默认10秒|
|anti_reply       |可选     |是否启用防重放策略，如启用则每次请求只能请求一次|
|policy           |可选     |用于查询是否重放请求的策略。当前仅支持`redis`|
|redis_host       |可选     |当使用 `redis` 防重放策略时，该属性是 Redis 服务节点的地址。|
|redis_port       |可选     |当使用 `redis` 防重放策略时，该属性是 Redis 服务节点的端口，默认端口 6379|
|redis_password   |可选     |当使用 `redis` 防重放策略时，该属性是 Redis 服务节点的密码。|
|redis_timeout    |可选     |当使用 `redis` 防重放策略时，该属性是 Redis 服务节点以毫秒为单位的超时时间，默认是 1000 ms（1 秒）|
|redis_keepalive  |可选     |当使用 `redis` 防重放策略时，该属性是 Redis 连接缓存时间，默认是 10000 ms（10秒）|
|redis_poolsize   |可选     |当使用 `redis` 防重放策略时，该属性是 Redis 连接池大小，默认是 100|

## 签名流程
请求Header中需要添加以下参数：

|名称           |可选项   |说明|
|--------------|--------|-----------|
|Appkey        |必选     |端应用的Key|
|Timestamp     |必选     |请求发出的时间戳|
|Sign          |必选     |签名值|
|Nonce         | 必选    |请求随机数|

签名计算规则：

```
sign = md5(encode_args(ngx.req.get_uri_args()) .. (ngx.req.get_body_data() or "") .. secret .. timestamp .. nonce)
```

#### 开启插件

下面是一个示例，在指定的 `route` 上开启了 `signature` 插件:

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

#### 测试插件

上述配置定义了route：/api/verify的各属性：

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

响应返回：

```
{"message":"invalid request, wrong signature"}
```

这就表示 `signature` 插件生效了。

#### 移除插件

当你想去掉 `signature` 插件的时候，很简单，在插件的配置中把对应的 json 配置删除即可，无须重启服务，即刻生效：

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

现在就已经移除了 `signature ` 插件了。其他插件的开启和移除也是同样的方法。
