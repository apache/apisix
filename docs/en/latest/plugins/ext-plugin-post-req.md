---
title: ext-plugin-post-req
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

`ext-plugin-post-req` is almost the same as `ext-plugin-pre-req`.

The only difference is that it runs after executing builtin Lua plugins and
before proxying to the upstream.

See the documentation of [ext-plugin-pre-req](./ext-plugin-pre-req.md) for how to configure it.
