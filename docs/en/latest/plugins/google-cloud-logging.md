---
title: google-cloud-logging
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

`google-cloud-logging` plugin is used to send the access log of `Apache APISIX` to the [Google Cloud Logging Service](https://cloud.google.com/logging/).

This plugin provides the ability to push log data as a batch to Google Cloud logging Service.

For more info on Batch-Processor in Apache APISIX please refer:
[Batch-Processor](../batch-processor.md)

## Attributes

| Name                    | Requirement   | Default                                                                                                                                                                                           | Description                                                                                                                                                                      |
| ----------------------- | ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| auth_config             | Semi-optional |                                                                                                                                                                                                   | one of `auth_config` or `auth_file` must be configured                                                                                                                           |
| auth_config.private_key | required      |                                                                                                                                                                                                   | the private key parameters of the Google service account                                                                                                                         |
| auth_config.project_id  | required      |                                                                                                                                                                                                   | the project id parameters of the Google service account                                                                                                                          |
| auth_config.token_uri   | optional      | https://oauth2.googleapis.com/token                                                                                                                                                               | the token uri parameters of the Google service account                                                                                                                           |
| auth_config.entries_uri | optional      | https://logging.googleapis.com/v2/entries:write                                                                                                                                                   | google cloud logging service API                                                                                                                                                       |
| auth_config.scopes      | optional      | ["https://www.googleapis.com/auth/logging.read","https://www.googleapis.com/auth/logging.write","https://www.googleapis.com/auth/logging.admin","https://www.googleapis.com/auth/cloud-platform"] | the access scopes parameters of the Google service account, refer to: [OAuth 2.0 Scopes for Google APIs](https://developers.google.com/identity/protocols/oauth2/scopes#logging) |
| auth_file               | semi-optional |                                                                                                                                                                                                   | path to the google service account json file（Semi-optional, one of auth_config or auth_file must be configured）                                                              |
| ssl_verify              | optional      | true                                                                                                                                                                                              | enable `SSL` verification, option as per [OpenResty docs](https://github.com/openresty/lua-nginx-module#tcpsocksslhandshake)                                                    |
| resource                | optional      | {"type": "global"}                                                                                                                                                                                | the Google monitor resource, refer to: [MonitoredResource](https://cloud.google.com/logging/docs/reference/v2/rest/v2/MonitoredResource)                                         |
| log_id                  | optional      | apisix.apache.org%2Flogs                                                                                                                                                                          | google cloud logging id, refer to: [LogEntry](https://cloud.google.com/logging/docs/reference/v2/rest/v2/LogEntry)                                                                     |

The plugin supports the use of batch processors to aggregate and process entries(logs/data) in a batch. This avoids frequent data submissions by the plugin, which by default the batch processor submits data every `5` seconds or when the data in the queue reaches `1000`. For information or custom batch processor parameter settings, see [Batch-Processor](../batch-processor.md#configuration) configuration section.

## How To Enable

The following is an example of how to enable the `google-cloud-logging` for a specific route.

### Full configuration

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "plugins": {
        "google-cloud-logging": {
            "auth_config":{
                "project_id":"apisix",
                "private_key":"-----BEGIN RSA PRIVATE KEY-----your private key-----END RSA PRIVATE KEY-----",
                "token_uri":"https://oauth2.googleapis.com/token",
                "scopes":[
                    "https://www.googleapis.com/auth/logging.admin"
                ],
                "entries_uri":"https://logging.googleapis.com/v2/entries:write"
            },
            "resource":{
                "type":"global"
            },
            "log_id":"apisix.apache.org%2Flogs",
            "inactive_timeout":10,
            "max_retry_count":0,
            "buffer_duration":60,
            "retry_delay":1,
            "batch_max_size":1
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

### Minimize configuration

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "plugins": {
        "google-cloud-logging": {
            "auth_config":{
                "project_id":"apisix",
                "private_key":"-----BEGIN RSA PRIVATE KEY-----your private key-----END RSA PRIVATE KEY-----"
            }
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

* Send request to route configured with the `google-cloud-logging` plugin

```shell
$ curl -i http://127.0.0.1:9080/hello
HTTP/1.1 200 OK
...
hello, world
```

* Login to Google Cloud to view logging service

[Google Cloud Logging Service](https://console.cloud.google.com/logs/viewer)

## Disable Plugin

Disabling the `google-cloud-logging` plugin is very simple, just remove the `JSON` configuration corresponding to `google-cloud-logging`.

```shell
$ curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
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
