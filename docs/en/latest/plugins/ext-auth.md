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

-[English](../../plugins/auth-hook.md)

# table of Contents

- [**Name**](#name)
- [**Attribute**](#Attribute)
- [**Dependencies**](#Dependencies)
- [**How to enable**](#How-to-enable)
- [**Test plugin**](#Test-plugin)
- [**Disable plugins**](#Disable-plugins)

## Name
`ext-auth` checks whether the incoming request is authorized by calling an external authorization service. If the request is deemed unauthorized by the network filter, the connection will be closed.
We configured `ext-auth` as the first filter in the filter chain to authorize the request before the remaining filters process the request.

## Attributes

| Name                      | Type          | Required | Default Value | Valid Value | Description                                                                                                                                                                                                                                                                                                                                                                                                              |
| ------------------------- | ------------- | -------- | ------------- | ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| ext_auth_url             | string        | 必选   |         |        | Set the access route of `auth-server` The plug-in will automatically carry the requested `path, action, client_ip` to the back of the domain name as the query parameter `?path=path&action=action&client_ip=client_ip`                                                                                                    |
| ext_auth_id              | string        | optional   | "unset" |        | Set `ext_auth_id`, the `ext_auth_id` will be carried in the header `Auth-Hook-Id` to request a custom auth-server service                                                                                                                                                                      |
| ext_auth_method          | string        | optional   | "GET"   |        | Set the access method of `auth-server`, the default is `GET`, only `POST`, `GET` are allowed                                                                                                                                                                                                           |
| ext_headers              | array[string] | optional   |         |        | Specify the header parameter of the business request. Proxy request ext_auth service, which will carry `Authorization` by default                                                                                                                                                                                               |
| ext_args                 | array[string] | optional   |         |        | Specify the request query parameter The proxy requests the ext_auth service with the query parameter                                                                                                                                                                                                                     |
| ext_auth_res_to_headers       | array[string] | optional   |         |        | |
| ext_auth_res_to_header_prefix | string        | optional   |     |        | |                                                                                                                                                                                                     |
| ext_auth_cache                | boolean       | optional   | false   |        | Whether to cache the data body of the same token request ext_auth service, the default is `false` According to your business situation, if it is enabled, it will be cached for 60S                                                                                                                                                                         |
| check_termination         | boolean       | optional   | true    |        |   Whether to request the auth-server to interrupt the request immediately after verification and return an error message, `true` is enabled by default to intercept and return immediately. If you set `false`, if the auth-server returns an error, it will continue to let you go, and set all the settings of `ext_auth_res_to_headers` Delete the mapping header field.                                                               |

## Dependencies

### Deploy your own auth service

The service needs to provide auth interface routing, and at least the following data structure is required to return the data body, we need the `data` data body

```json
{
    "message":"success",
    "data":{
        "user_id":15,
        "......": "......"
    }
}
```

## How to enable

1. Create a Route or Service object and enable the `ext-auth` plugin.

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/*",
    "plugins": {
        "auth-hook": {
            "ext_auth_id": "order",
            "ext_auth_method": "POST",
            "ext_auth_url": "http://common-user-pro_1.dev.xthktech.cn/api/user/gateway-auth",
            "ext_auth_cache": false,
            "ext_auth_check_termination": true,
            "ext_auth_headers": [
                "X-app-name"   ],
            "ext_auth_res_to_header_prefix": "XT-",
            "ext_auth_res_to_header": [
                "user_id",
                "student_id"]
            }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "www.baidu.com:80": 1
        }
    }
 }'
```

## Test plugin


## Disable plugin

When you want to remove the `ext-auth` plug-in, it is very simple, just delete the corresponding `plug-in` configuration in the plug-in configuration in routes, no need to restart the service, it will take effect immediately:

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/*",
    "plugins": {
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "www.baidu.com:80": 1
        }
    }
}'
```