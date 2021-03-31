---
title: Plugin
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

`Plugin` represents the plugin configuration that will be executed during the `HTTP` request/response lifecycle.

The `Plugin` configuration can be bound directly to `Route` or it can be bound to `Service` or `Consumer`. For the configuration of the same plugin, only one copy is valid, and the configuration selection priority is always `Consumer` > `Route` > `Service`.

In `conf/config.yaml`, you can declare which plugins are supported by the local APISIX node. This is a whitelisting mechanism. Plugins that are not in this whitelist will be automatically ignored. This feature can be used to temporarily turn off or turn on specific plugins, which is very effective in dealing with unexpected situations. If you want to add new plugins based on existing plugins, you need to copy the data of `plugins` node which in `conf/config-default.yaml` to the `plugins` node of `conf/config.yaml`.

The configuration of the plugin can be directly bound to the specified Route, or it can be bound to the Service, but the plugin configuration in Route has a higher priority.

A plugin will only be executed once in a single request, even if it is bound to multiple different objects (such as Route or Service).

The order in which plugins are run is determined by the priority of the plugin itself, for example:

```lua
local _M = {
    version = 0.1,
    priority = 0, -- the priority of this plugin will be 0
    name = plugin_name,
    schema = schema,
    metadata_schema = metadata_schema,
}
```

The plugin configuration is submitted as part of Route or Service and placed under `plugins`. It internally uses the plugin name as the hash's key to hold configuration items for different plugins.

```json
{
    ...
    "plugins": {
        "limit-count": {
            "count": 2,
            "time_window": 60,
            "rejected_code": 503,
            "key": "remote_addr"
        },
        "prometheus": {}
    }
}
```

Not all plugins have specific configuration items. For example, there is no specific configuration item under `prometheus`. In this case, an empty object identifier can be used.

If a request is rejected by a plugin, there will be warn level log like `ip-restriction exits with http status code 403`.
