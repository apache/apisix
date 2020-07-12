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

# Summary
- [**Name**](#name)
- [**Attributes**](#attributes)
- [**How To Enable**](#how-to-enable)
- [**Test Plugin**](#test-plugin)
- [**Disable Plugin**](#disable-plugin)


## Name

`http-logger` is a plugin which push Log data requests to HTTP/HTTPS servers.

This will provide the ability to send Log data requests as JSON objects to Monitoring tools and other HTTP servers.

## Attributes

|Name           |Requirement    |Description|
|---------      |--------       |-----------|
|uri            |required       |URI of the server|
|authorization  |optional       |Any authorization headers|
|keepalive      |optional       |Time to keep the connection alive after sending a request|
|name           |optional       |A unique identifier to identity the logger|
|batch_max_size |optional       |Max size of each batch, default is 1000|
|inactive_timeout|optional      |maximum age in seconds when the buffer will be flushed if inactive, default is 5s|
|buffer_duration|optional       |Maximum age in seconds of the oldest entry in a batch before the batch must be processed, default is 5|
|max_retry_count|optional       |Maximum number of retries before removing from the processing pipe line; default is zero|
|retry_delay    |optional       |Number of seconds the process execution should be delayed if the execution fails; default is 1|


## How To Enable

The following is an example on how to enable the http-logger for a specific route.

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/5 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
      "plugins": {
            "http-logger": {
                 "uri": "127.0.0.1:80/postendpoint?param=1",
            }
       },
      "upstream": {
           "type": "roundrobin",
           "nodes": {
               "127.0.0.1:1980": 1
           }
      },
      "uri": "/hello"
}'
```

## Test Plugin

* success:

```shell
$ curl -i http://127.0.0.1:9080/hello
HTTP/1.1 200 OK
...
hello, world
```

## Disable Plugin

Remove the corresponding json configuration in the plugin configuration to disable the `http-logger`.
APISIX plugins are hot-reloaded, therefore no need to restart APISIX.

```shell
$ curl http://127.0.0.1:2379/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d value='
{
    "methods": ["GET"],
    "uri": "/hello",
    "plugins": {},
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```
