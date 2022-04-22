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

`Script` 表示将在 `HTTP` 请求/响应生命周期期间执行的脚本。

`Script` 配置可直接绑定在 `Route` 上。

`Script` 与 `Plugin` 互斥，且优先执行 `Script` ，这意味着配置 `Script` 后，`Route` 上配置的 `Plugin` 将不被执行。

理论上，在 `Script` 中可以写任意 lua 代码，也可以直接调用已有插件以重用已有的代码。

`Script` 也有执行阶段概念，支持 `access`、`header_filter`、`body_filter` 和 `log` 阶段。系统会在相应阶段中自动执行 `Script` 脚本中对应阶段的代码。

```json
{
    ...
    "script": "local _M = {} \n function _M.access(api_ctx) \n ngx.log(ngx.INFO,\"hit access phase\") \n end \nreturn _M"
}
```
