---
title: ext-plugin-post-req
keywords:
  - Apache APISIX
  - Plugin
  - ext-plugin-post-req
description: This document contains information about the Apache APISIX ext-plugin-post-req Plugin.
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

`ext-plugin-post-req` differs from the [ext-plugin-pre-req](./ext-plugin-pre-req.md) Plugin in that it runs after executing the built-in Lua Plugins and before proxying to the Upstream.

You can learn more about the configuration from the [ext-plugin-pre-req](./ext-plugin-pre-req.md) Plugin document.
