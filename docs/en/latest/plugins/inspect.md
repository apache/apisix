---
title: inspect
keywords:
  - APISIX
  - Plugin
  - inspect
  - inspect
description: This document contains information about the Apache APISIX inspect Plugin.
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

It's useful to set arbitrary breakpoint in any lua file to inspect the context information,
e.g. print local variables if some condition satisfied.

In this way, you don't need to modify the source code of your project, and just get diagnose information
on demand, i.e. dynamic logging.

This plugin supports setting breakpoints within both interpretd function and jit compiled function.
The breakpoint could be at any position within the function. The function could be global/local/module/ananymous.

## Features

* set breakpoint at any position
* dynamic breakpoint
* Customized breakpoint handler
* you could define one-shot breakpoint
* work for jit compiled function
* if function reference specified, then performance impact is only bound to that function (JIT compiled code will not trigger debug hook, so they would run fast even if hook is enabled)
* if all breakpoints deleted, jit could recover

## Operation Graph

![Operation Graph](https://raw.githubusercontent.com/apache/apisix/master/docs/assets/images/plugin/inspect.png)

## API to define hook in hooks file

### require("resty.inspect.dbg").set_hook(file, line, func, filter_func)

The breakpoint is specified by `file` (full qualified or short file name) and the `line` number.

The `func` specified the scope (which function or global) of jit cache to flush:

* If the breakpoint is related to a module function or
global function, you should set it that function reference, then only the jit cache of that function would
be flushed, and it would not affect other caches to avoid slowing down other parts of the program.

* If the breakpointis related to local function or anonymous function,
then you have to set it to `nil` (because no way to get function reference), which would flush the whole jit cache of lua vm.

You attach a `filter_func` function of the breakpoint, the function takes the `info` as argument and returns
true of false to determine whether the breakpoint would be removed. You could setup one-shot breakpoint
at ease.

The `info` is a hash table which contains below keys:

* `finfo`: `debug.getinfo(level, "nSlf")`
* `uv`: upvalues hash table
* `vals`: local variables hash table

## Attributes

| Name               | Type    | Required | Default | Description                                                                                    |
|--------------------|---------|----------|---------|------------------------------------------------------------------------------------------------|
| delay           | integer | False     | 3 | Time in seconds specifying how often to rotate the check the hooks file.                                       |
| hooks_file           | string | False     | "/var/run/apisix_inspect_hooks.lua"  | lua file to define hooks. |

## Enabling the Plugin

Plugin is enabled by default (`conf/config-default.yaml`):

```yaml title="conf/config-default.yaml"
plugins:
    - inspect

plugin_attr:
  inspect:
    delay: 3
    hooks_file: "/var/run/apisix_inspect_hooks.lua"
```

## Configuration description

TODO.

## Example usage

TODO.

## Disable plugin

To remove the `log-rotate` Plugin, you can remove it from your configuration file (`conf/config.yaml`):

```yaml title="conf/config.yaml"
plugins:
    # - log-rotate
```
