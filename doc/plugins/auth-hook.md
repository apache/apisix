<!--
#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements. See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License. You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
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

-[**Name**](#名) -[**Attribute**](#Attribute) -[**Dependencies**](#Dependencies) -[**How ​​to enable**](#How to enable) -[**Test plugin**](#Test plugin) -[**Disable plugins**](#Disable plugins)

## first name

`auth-hook` is an authentication and authorization plug-in, it needs to cooperate with `consumer` to work. At the same time, you need to add `auth-hook` to a `service` or `route`.
The auth-hook function is provided by its own auth-server, and it is sufficient to provide an authorization authentication interface according to the corresponding data structure.

## Attributes

| Name                      | Type          | Required | Default Value | Valid Value | Description                                                                                                                                                                                                                                                                                                                                                                                                           |
| ------------------------- | ------------- | -------- | ------------- | ----------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| hook_uri                  | string        | Required |               |             | Set the access route of `auth-server`                                                                                                                                                                                                                                                                                                                                                                                 |
| auth_id                   | string        | Optional | "unset"       |             | Set `auth_id`, this `auth_id` needs to be carried in the header of the business request `x-auth-id` or carried in the query `auth_id`                                                                                                                                                                                                                                                                                 |
| hook_headers              | array[string] | Optional |               |             | Specify request header parameters proxy request hook service                                                                                                                                                                                                                                                                                                                                                          |
| hook_args                 | array[string] | Optional |               |             | Specify request query parameters, proxy requests hook service with query parameters                                                                                                                                                                                                                                                                                                                                   |
| hook_res_to_headers       | array[string] | Optional |               |             | Specify the fields in the data body of the data returned by the hook service, add the headers parameter and pass it to the upstream service, such as `user_id=15` in the data data, splicing `hook_res_to_header_prefix` and Replace the next `_` with `-` in the header, request upstream services with `X-user-id`, if the selected field is an object or array, it will be converted to a json string as its value |
| hook_res_to_header_prefix | string        | Optional |               |             | User `hook_res_to_headers` carries parameters and converts to the prefix of the header field                                                                                                                                                                                                                                                                                                                          |
| hook_cache                | boolean       | Optional | false         |             | Whether to cache the data body of the same token request hook service, the default is `false` according to your own business situation                                                                                                                                                                                                                                                                                |

## Dependencies

### Deploy your own auth service

The service needs to provide auth interface routing, and at least the following data structure is required to return the data body,

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

1. Create a consumer object and set the value of the plug-in `auth-hook`.

```shell
curl http://127.0.0.1:9080/apisix/admin/consumers -H'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
  "username": "auth_hook",
  "plugins": {
    "auth-hook": {
      "hook_uri": "http://127.0.0.1/xxxx/xxx",
      "auth_id": "shaozeming",
      "hook_headers": [
        "X-APP-NAME",
        "..."
      ],
      "hook_args": [
        "field_1",
        "..."
      ],
      "hook_res_to_headers": [
        "user_id",
        "..."
      ]
    }
  },
  "desc": "auth-hook"
}'
```

You can use a browser to open the dashboard: `http://127.0.0.1:9080/apisix/dashboard/`, complete the above operations through the web interface, first add a consumer, and then add the auth-hook plugin to the consumer page

2. Create a Route or Service object and enable the `auth-hook` plugin.

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/*",
    "plugins": {
        "auth-hook": {}
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

#### First log in to the hook-server service to obtain a custom `auth-hook` token:

Assume that the user token acquired as `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWNlbnRlciIsIm5iZiI6MTYxMjA2MzI1NCwic3R1ZGVudF9pZCI6NjU1ODQ3LCJ1c2VyX2lkIjo5NzAwNjF9.3K5-cb8tlsk_rz-76_1ET-Oik9vQG2vFJk662CLl_aQ`

#### Use the obtained token to make a request attempt

-Missing token

```shell
curl http://127.0.0.1:9080/ -H"Host: www.baidu.com" -i

HTTP/1.1 401 Unauthorized
...
{"message":"Missing auth token in request"}
```

-The token is placed in the request header (Authorization):

```shell
curl http://127.0.0.1:9080/ -H"Host: www.baidu.com" \
-H 'Authorization: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWNlbnRlciIsIm5iZiI6MTYxMjA2MzI1NCwic3R1ZGVudF9pZCI6NjU1ODQ3LCJ1c2VyX2lkIjo5NzAwNjF9.3K5-cb8tlsk_rz-76_1ET-Oik9vQG2vFJk662CLl_aQ' -H 'X-Auth-Id: shaozeming' -i

HTTP/1.1 200 OK

<!DOCTYPE html>
```

-Put token in the request header (x-auth-token):

```shell
curl http://127.0.0.1:9080/ -H"Host: www.baidu.com" \
-H 'x-auth-token: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWNlbnRlciIsIm5iZiI6MTYxMjA2MzI1NCwic3R1ZGVudF9pZCI6NjU1ODQ3LCJ1c2VyX2lkIjo5NzAwNjF9.3K5-cb8tlsk_rz-76_1ET-Oik9vQG2vFJk662CLl_aQ' -H 'X-Auth-Id: shaozeming' -i


HTTP/1.1 200 OK

<!DOCTYPE html>
```

-The token is placed in the request parameters:

```shell
curl 'http://127.0.0.1:9080?auth_token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWNlbnRlciIsIm5iZiI6MTYxMjA2MzI1NCwic3R1ZGVudF9pZCI6NjU1ODQ3LCJ1c2VyX2lkIjo5NzAwNjF9.3K5-cb8tlsk_rz-76_1ET-Oik9vQG2vFJk662CLl_aQ&auth_id=shaozeming' -i


HTTP/1.1 200 OK

<!DOCTYPE html>
```

## Disable plugin

When you want to remove the `auth-hook` plug-in, it is very simple, just delete the corresponding `plug-in` configuration in the plug-in configuration in routes, no need to restart the service, it will take effect immediately:

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
