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

## Hot reload

APISIX plugins are hot-loaded. No matter you add, delete or modify plugins, and **update codes of plugins in disk**, you don't need to restart the service.

If your APISIX node has the Admin API turned on, just send an HTTP request through admin API:

```shell
curl http://127.0.0.1:9080/apisix/admin/plugins/reload -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT
```

Note: if you disable a plugin which has been configured as part of your rule (in the `plugins` field of `route`, etc.),
the its execution will be skipped.

### Hot reload in stand-alone mode

For stand-alone mode, see plugin related section in [stand alone mode](stand-alone.md).
