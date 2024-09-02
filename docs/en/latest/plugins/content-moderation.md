---
title: content-moderation
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - content-moderation
description: This document contains information about the Apache APISIX content-moderation Plugin.
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

The `content-moderation` plugin processes the request body to check for toxicity and rejects the request if it exceeds the configured threshold.

## Plugin Attributes

| **Field**                                 | **Required** | **Type** | **Description**                                                                                                                          |
| ----------------------------------------- | ------------ | -------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| provider.aws_comprehend.access_key_id     | Yes          | String   | AWS access key ID                                                                                                                        |
| provider.aws_comprehend.secret_access_key | Yes          | String   | AWS secret access key                                                                                                                    |
| provider.aws_comprehend.region            | Yes          | String   | AWS region                                                                                                                               |
| provider.aws_comprehend.endpoint          | No           | String   | AWS Comprehend service endpoint. Must match the pattern `^https?://`                                                                     |
| moderation_categories                     | No           | Object   | Configuration for moderation categories. Must be one of: PROFANITY, HATE_SPEECH, INSULT, HARASSMENT_OR_ABUSE, SEXUAL, VIOLENCE_OR_THREAT |
| toxicity_level                            | No           | Number   | Threshold for overall toxicity detection. Range: 0 - 1. Default: 0.5                                                                     |

## Example usage

Create a route with the `content-moderation` plugin like so:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "uri": "/post",
    "plugins": {
      "content-moderation": {
        "provider": {
          "aws_comprehend": {
            "access_key_id": "access",
            "secret_access_key": "ea+secret",
            "region": "us-east-1"
          }
        },
        "moderation_categories": {
          "PROFANITY": 0.5
        }
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

Now send a request:

```shell
curl http://127.0.0.1:9080/post -i -XPOST  -H 'Content-Type: application/json' -d '{
  "info": "<some very seriously profane message>"
}'
```

Then the request will be blocked with error like this:

```text
HTTP/1.1 400 Bad Request
Date: Fri, 30 Aug 2024 11:21:21 GMT
Content-Type: text/plain; charset=utf-8
Transfer-Encoding: chunked
Connection: keep-alive
Server: APISIX/3.10.0

request body exceeds toxicity threshold
```

Send a request with normal request body:

```shell
curl http://127.0.0.1:9080/post -i -XPOST  -H 'Content-Type: application/json' -d 'APISIX is wonderful'
```

This request will be proxied normally to the upstream.

```text
HTTP/1.1 200 OK
Content-Type: application/json
Content-Length: 530
Connection: keep-alive
Date: Fri, 30 Aug 2024 11:21:55 GMT
Access-Control-Allow-Origin: *
Access-Control-Allow-Credentials: true
Server: APISIX/3.10.0

{
  "args": {},
  "data": "",
  "files": {},
  "form": {
    "APISIX is wonderful": ""
  },
  "headers": {
    "Accept": "*/*",
    "Content-Length": "67",
    "Content-Type": "application/x-www-form-urlencoded",
    "Host": "127.0.0.1",
    "User-Agent": "curl/8.7.1",
    "X-Amzn-Trace-Id": "Root=1-66d1ab53-0860444b1b01a3f93c7003f4",
    "X-Forwarded-Host": "127.0.0.1"
  },
  "json": null,
  "origin": "127.0.0.1, 163.53.25.129",
  "url": "http://127.0.0.1/post"
}
```

You can also configure filters on other moderation categories like so:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "uri": "/post",
    "plugins": {
      "content-moderation": {
        "provider": {
          "aws_comprehend": {
            "access_key_id": "access",
            "secret_access_key": "ea+secret",
            "region": "us-east-1"
          }
        },
        "moderation_categories": {
          "PROFANITY": 0.5,
          "HARASSMENT_OR_ABUSE": 0.7,
          "SEXUAL": 0.2
        }
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

If none of the `moderation_categories` are configured, request bodies will be moderated on the basis of overall toxicity.
The default `toxicity_level` is 0.5, it can be configured like so.

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "uri": "/post",
    "plugins": {
      "content-moderation": {
        "provider": {
          "aws_comprehend": {
            "access_key_id": "access",
            "secret_access_key": "ea+secret",
            "region": "us-east-1"
          }
        }
        "toxicity_level": 0.7
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
