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

- [**Name**](#Name)
- [**Requirement**](#Requirement)
- [**Runtime Attributes**](#Runtime-Attributes)
- [**Static Attributes**](#Static-Attributes)
- [**How To Enable**](#How-To-Enable)
- [**Test Plugin**](#Test-Plugin)
- [**Disable Plugin**](#Disable-Plugin)

## Name

dubbo-proxy plugin allows you proxy HTTP request to [**dubbo**](http://dubbo.apache.org).

## Requirement

If you are using OpenResty, you need to build it with dubbo support, see [How to build](https://github.com/api7/mod_dubbo#how-to-build).

To make http2dubbo work in APISIX, we enhance the dubbo module based on Tengine's `mod_dubbo`. The modifications are contributed back to Tengine, but they are not included in the latest release version (Tengine-2.3.2) yet. So Tengine itself is unsupported.

## Runtime Attributes

| Name         | Type   | Requirement | Default  | Valid        | Description                                                          |
| ------------ | ------ | ----------- | -------- | ------------ | -------------------------------------------------------------------- |
| service_name    | string | required    |          |              | dubbo provider service name|
| service_version | string | required    |          |              | dubbo provider service version|
| method          | string | optional    | the path of uri   |     | dubbo provider service method|

## Static Attributes

| Name         | Type   | Requirement | Default  | Valid        | Description                                                          |
| ------------ | ------ | ----------- | -------- | ------------ | -------------------------------------------------------------------- |
| upstream_multiplex_count | number | required    | 32        | >= 1 | the maximum number of multiplex requests in an upstream connection |

## How To Enable

First of all, enable the dubbo-proxy plugin in the `config.yaml`:

```
# Add this in config.yaml
plugins:
  - ... # plugin you need
  - dubbo-proxy
```

Then reload APISIX.

Here's an example, enable the dubbo-proxy plugin on the specified route:

```shell
curl http://127.0.0.1:9080/apisix/admin/upstream/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "nodes": {
        "127.0.0.1:20880": 1
    },
    "type": "roundrobin"
}'

curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uris": [
        "/hello"
    ],
    "plugins": {
        "dubbo-proxy": {
            "service_name": "org.apache.dubbo.sample.tengine.DemoService",
            "service_version": "0.0.0",
            "method": "tengineDubbo"
        }
    },
    "upstream_id": 1
}'
```

## Test Plugin

You can follow the [Quick Start](https://github.com/alibaba/tengine/tree/master/modules/mod_dubbo#quick-start) example in Tengine and use the configuration above to test it.
They should provide the same result.

## Disable Plugin

When you want to disable the dubbo-proxy plugin on a route/service, it is very simple,
 you can delete the corresponding json configuration in the plugin configuration,
  no need to restart the service, it will take effect immediately:

```shell
$ curl http://127.0.0.1:2379/v2/keys/apisix/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d value='
{
    "methods": ["GET"],
    "uris": [
        "/hello"
    ],
    "plugins": {
    },
    "upstream_id": 1
    }
}'
```

The dubbo-proxy plugin has been disabled now. It works for other plugins.

If you want to disable dubbo-proxy plugin totally,
you need to comment out in the `config.yaml`:

```yaml
plugins:
  - ... # plugin you need
  #- dubbo-proxy
```

And then reload APISIX.
