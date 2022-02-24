---
title: The Implementation of Plugin Runner
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

## Prerequirement

Each request which runs the extern plugin will trigger an RPC to Plugin Runner over a connection on Unix socket. The data of RPC are serialized with [Flatbuffers](https://github.com/google/flatbuffers).

Therefore, the Plugin Runner needs to:

1. handle a connection on Unix socket
2. support Flatbuffers
3. use the proto & generated code in https://github.com/api7/ext-plugin-proto/

## Listening to the Path

APISIX will pass the path of Unix socket as an environment variable `APISIX_LISTEN_ADDRESS` to the Plugin Runner. So the runner needs to read the value and listen to that address during starting.

## Register Plugins

The Plugin Runner should be able to load plugins written in the particular language.

## Handle RPC

There are two kinds of RPC: PrepareConf & HTTPReqCall

### Handle PrepareConf

As people can configure the extern plugin on the side of APISIX, we need a way to sync the plugin configuration to the Plugin Runner.

When there is a configuration that needs to sync to the Plugin Runner, we will send it via the PrepareConf RPC call. The Plugin Runner should be able to handle the call and store the configuration in a cache, then returns a unique conf token that represents the configuration.

In the previous design, an idempotent key is sent with the configuration. This field is deprecated and the Plugin Runner can safely ignore it.

Requests run plugins with particular configuration will bear a particular conf token in the RPC call, and the Plugin Runner is expected to look up actual configuration via the token.

When the configuration is modified, APISIX will send a new PrepareConf to the Plugin Runner. Currently, there is no way to notify the Plugin Runner that a configuration is removed. Therefore, we introduce another environment variable `APISIX_CONF_EXPIRE_TIME` as the conf cache expire time. The Plugin Runner should be able to cache the conf slightly longer than `APISIX_CONF_EXPIRE_TIME`, and APISIX will send another PrepareConf to refresh the cache if the configuration is still existing after `APISIX_CONF_EXPIRE_TIME` seconds.

### Handle HTTPReqCall

Each request which runs the extern plugin will trigger the HTTPReqCall. The HTTPReqCall is almost a serialized version of HTTP request, plus a conf token. The Plugin Runner is expected to tell APISIX what to update by the response of HTTPReqCall RPC call.

Sometimes the plugin in the Plugin Runner needs to know some information that is not part of the HTTPReqCall request, such as the request start time and the route ID in APISIX. Hence the Plugin Runner needs to reply to an `ExtraInfo` message as the response on the connection which sends the HTTPReqCall request. APISIX will read the `ExtraInfo` message and return the asked information.

Currently, the information below is passed by `ExtraInfo`:

* variable value
* request body

The flow of HTTPReqCall procession is:

```
APISIX sends HTTPReqCall
Plugin Runner looks up the plugin configuration by the token in HTTPReqCall
(optional) loop:
    Plugin Runner asks for ExtraInfo
    APISIX replies the ExtraInfo
Plugin Runner replies HTTPReqCall
```
