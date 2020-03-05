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

[Chinese](serverless-cn.md)

# Summary
- [**Name**](#name)
- [**Attributes**](#attributes)
- [**How To Enable**](#how-to-enable)
- [**Test Plugin**](#test-plugin)
- [**Disable Plugin**](#disable-plugin)

## Name

There are two plug-ins for serverless, namely `serverless-pre-function` and `serverless-post-function`.

The former runs at the beginning of the specified phase, while the latter runs at the end of the specified phase.

Both plug-ins receive the same parameters.

## Attributes

|Name          |Requirement  |Description|
|---------     |--------|-----------|
| phase         |optional|The default phase is `access`, if not specified. The valid phases are: `rewrite`, `access`,`Header_filer`, `body_filter`, `log` and `balancer`.|
| functions         |required|A list of functions that are specified to run is an array type, which can contain either one function or multiple functions, executed sequentially.|


Note that only function is accepted here, not other types of Lua code. For example, anonymous functions are legal:<br>
```
return function()
    ngx.log(ngx.ERR, 'one')
end
```

Closure is also legal:
```
local count = 1
return function()
    count = count + 1
    ngx.say(count)
end
```

But code that is not a function type is illegal:
 ```
local count = 1
ngx.say(count)
```

## How To Enable

Here's an example, enable the serverless plugin on the specified route:

```shell
curl -i http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/index.html",
    "plugins": {
        "serverless-pre-function": {
            "phase": "rewrite",
            "functions" : ["return function() ngx.log(ngx.ERR, \"serverless pre function\"); end"]
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

## Test Plugin

 Use curl to access:
 ```shell
curl -i http://127.0.0.1:9080/index.html
```

Then you will find the message 'serverless pre-function' in the error.log,
which indicates that the specified function is in effect.

## Disable Plugin

When you want to disable the serverless plugin, it is very simple,
 you can delete the corresponding json configuration in the plugin configuration,
  no need to restart the service, it will take effect immediately:

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/index.html",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "39.97.63.215:80": 1
        }
    }
}'
```

The serverless plugin has been disabled now. It works for other plugins.
