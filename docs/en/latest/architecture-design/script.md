---
title: Script
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

`Script` represents a script that will be executed during the `HTTP` request/response life cycle.

The `Script` configuration can be directly bound to the `Route`.

`Script` and `Plugin` are mutually exclusive, and `Script` is executed first. This means that after configuring `Script`, the `Plugin` configured on `Route` will not be executed.

In theory, you can write arbitrary Lua code in `Script`, or you can directly call existing plugins to reuse existing code.

`Script` also has the concept of execution phase, supporting `access`, `header_filter`, `body_filter` and `log` phase. The system will automatically execute the code of the corresponding phase in the `Script` script in the corresponding phase.

```json
{
    ...
    "script": "local _M = {} \n function _M.access(api_ctx) \n ngx.log(ngx.INFO,\"hit access phase\") \n end \nreturn _M"
}
```
