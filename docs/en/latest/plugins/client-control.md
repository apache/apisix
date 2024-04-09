---
title: client-control
keywords:
  - Apache APISIX
  - API Gateway
  - Client Control
description: This document describes the Apache APISIX client-control Plugin, you can use it to control NGINX behavior to handle a client request dynamically.
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

The `client-control` Plugin can be used to dynamically control the behavior of NGINX to handle a client request, by setting the max size of the request body.

:::info IMPORTANT

This Plugin requires APISIX to run on APISIX-Runtime. See [apisix-build-tools](https://github.com/api7/apisix-build-tools) for more info.

:::

## Attributes

| Name          | Type    | Required | Valid values | Description                                                                                                                          |
| ------------- | ------- | -------- | ------------ | ------------------------------------------------------------------------------------------------------------------------------------ |
| max_body_size | integer | False    | [0,...]      | Set the maximum limit for the client request body and dynamically adjust the size of [`client_max_body_size`](https://nginx.org/en/docs/http/ngx_http_core_module.html#client_max_body_size), measured in bytes. If you set the `max_body_size` to 0, then the size of the client's request body will not be checked. |

## Enable Plugin

The example below enables the Plugin on a specific Route:

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl -i http://127.0.0.1:9180/apisix/admin/routes/1 \
  -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/index.html",
    "plugins": {
        "client-control": {
            "max_body_size" : 1
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```

## Example usage

Now since you have configured the `max_body_size` to `1` above, you will get the following message when you make a request:

```shell
curl -i http://127.0.0.1:9080/index.html -d '123'
```

```shell
HTTP/1.1 413 Request Entity Too Large
...
<html>
<head><title>413 Request Entity Too Large</title></head>
<body>
<center><h1>413 Request Entity Too Large</h1></center>
<hr><center>openresty</center>
</body>
</html>
```

## Delete Plugin

To remove the `client-control` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload, and you do not have to restart for this to take effect.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  \
  -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/index.html",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```
