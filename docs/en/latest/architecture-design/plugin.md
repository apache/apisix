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

This represents the configuration of the plugins that are executed during the HTTP request/response lifecycle.

A `Plugin` configuration can be bound directly to a [`Route`](./route.md), a [`Service`](./service.md) or a [`Consumer`](./consumer.md).

**Note**: While configuring the same plugin, only one copy of the configuration is valid. The order of precedence is always `Consumer` > `Route` > `Service`.

While [configuring APISIX](./apisix.md#configuring-apisix), you can declare the Plugins that are supported by the local APISIX node.

This acts as a whitelisting mechanism as Plugins that are not in this whitelist will be automatically ignored. So, this feature can be used to temporarily turn off/turn on specific plugins.

For adding new plugins based on existing plugins, copy the data in the the `plugins` node from the default configuration file `conf/config-default.yaml` to your configuration file (`conf/config.yaml`).

In a request, a Plugin is only executed once. This is true even if it is bound to multiple different objects like Routes and Services.

The order in which Plugins are run is determined by its configured priorities:

```lua
local _M = {
    version = 0.1,
    priority = 0, -- the priority of this plugin will be 0
    name = plugin_name,
    schema = schema,
    metadata_schema = metadata_schema,
}
```

A Plugin configuration is submitted as part of the Route or Service and is placed under `plugins`. It internally uses the Plugin name as the hash key to hold the configuration items for the different Plugins.

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

Not all Plugins have specific configuration items (for example, [prometheus](/docs/apisix/plugins/prometheus/)). In such cases, an empty object identifier can be used.

A warn level log as shown below indicates that the request was rejected by the Plugin.

```shell
ip-restriction exits with http status code 403
```

## Hot Reload

APISIX Plugins are hot-loaded.

This means that there is no need to restart the service if you add, delete, modify plugins or even if you update the plugin code.

To hot-reload, you can send an HTTP request through the [Admin API](../admin-api.md):

```shell
curl http://127.0.0.1:9080/apisix/admin/plugins/reload -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT
```

**Note**: If a configured Plugin is disabled, then its execution will be skipped.

### Hot reload in stand-alone mode

For hot-reloading in stand-alone mode, see the plugin related section in [stand alone mode](../stand-alone.md).
