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

The control API can be used to

* expose APISIX internal state
* control the behavior of a single isolate APISIX data panel

By default, the control API server is enabled and listens to `127.0.0.1:9090`. You can change it via
the `control` section under `apisix` in `conf/config.yaml`:

```yaml
apisix:
  ...
  enable_control: true
  control:
    ip: "127.0.0.1"
    port: 9090
```

Note that the control API server should not be configured to listen to the public traffic!

## Control API Added via plugin

Plugin can add its control API when it is enabled.
If a plugin adds such a control API, please refer to each plugin's documentation for those APIs.

## Plugin independent Control API

Here is the supported API:

### GET /v1/schema

Introduced since `v2.2`.

Return the jsonschema used by this APISIX instance in the format below:

```json
{
    "main": {
        "route": {
            "properties": {...}
        },
        "upstream": {
            "properties": {...}
        },
        ...
    },
    "plugins": {
        "example-plugin": {
            "consumer_schema": {...},
            "metadata_schema": {...},
            "schema": {...},
            "type": ...,
            "priority": 0,
            "version": 0.1
        },
        ...
    }
}
```

For `plugins` part, only enabled plugins will be returned. Some plugins may lack
of fields like `consumer_schema` or `type`, it is dependended by the plugin's
definition.
