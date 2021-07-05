---
title: APISIX Lua Coding Style Guide
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

## Indentation

Use 4 spaces as an indent:

```lua
--No
if a then
ngx.say("hello")
end
```

```lua
--Yes
if a then
    ngx.say("hello")
end
```

You can simplify the operation by changing the tab to 4 spaces in the editor you are using.

## Space

On both sides of the operator, you need to use a space to separate:

```lua
--No
local i=1
local s    =    "apisix"
```

```lua
--Yes
local i = 1
local s = "apisix"
```

## Blank line

Many developers will add a semicolon at the end of the line:

```lua
--No
if a then
    ngx.say("hello");
end;
```

Adding a semicolon will make the Lua code look ugly and unnecessary. Also, don't want to save the number of lines in the code, the latter turns the multi-line code into one line in order to appear "simple". This will not know when the positioning error is in the end of the code:

```lua
--No
if a then ngx.say("hello") end
```

```lua
--Yes
if a then
    ngx.say("hello")
end
```

The functions needs to be separated by two blank lines:

```lua
--No
local function foo()
end
local function bar()
end
```

```lua
--Yes
local function foo()
end


local function bar()
end
```

If there are multiple if elseif branches, they need a blank line to separate them:

```lua
--No
if a == 1 then
    foo()
elseif a== 2 then
    bar()
elseif a == 3 then
    run()
else
    error()
end
```

```lua
--Yes
if a == 1 then
    foo()

elseif a== 2 then
    bar()

elseif a == 3 then
    run()

else
    error()
end
```

## Maximum length per line

Each line cannot exceed 100 characters. If it exceeds, you need to wrap and align:

```lua
--No
return limit_conn_new("plugin-limit-conn", conf.conn, conf.burst, conf.default_conn_delay)
```

```lua
--Yes
return limit_conn_new("plugin-limit-conn", conf.conn, conf.burst,
                      conf.default_conn_delay)
```

When the linefeed is aligned, the correspondence between the upper and lower lines should be reflected. For the example above, the parameters of the second line of functions are to the right of the left parenthesis of the first line.

If it is a string stitching alignment, you need to put `..` in the next line:

```lua
--No
return limit_conn_new("plugin-limit-conn" ..  "plugin-limit-conn" ..
                      "plugin-limit-conn")
```

```lua
--Yes
return limit_conn_new("plugin-limit-conn" .. "plugin-limit-conn"
                      .. "plugin-limit-conn")
```

```lua
--Yes
return "param1", "plugin-limit-conn"
                 .. "plugin-limit-conn"
```

## Variable

Local variables should always be used, not global variables:

```lua
--No
i = 1
s = "apisix"
```

```lua
--Yes
local i = 1
local s = "apisix"
```

Variable naming uses the `snake_case` style:

```lua
--No
local IndexArr = 1
local str_Name = "apisix"
```

```lua
--Yes
local index_arr = 1
local str_name = "apisix"
```

Use all capitalization for constants:

```lua
--No
local max_int = 65535
local server_name = "apisix"
```

```lua
--Yes
local MAX_INT = 65535
local SERVER_NAME = "apisix"
```

## Table

Use `table.new` to pre-allocate the table:

```lua
--No
local t = {}
for i = 1, 100 do
    t[i] = i
end
```

```lua
--Yes
local new_tab = require "table.new"
local t = new_tab(100, 0)
for i = 1, 100 do
    t[i] = i
end
```

Don't use `nil` in an array:

```lua
--No
local t = {1, 2, nil, 3}
```

If you must use null values, use `ngx.null` to indicate:

```lua
--Yes
local t = {1, 2, ngx.null, 3}
```

## String

Do not splicing strings on the hot code path:

```lua
--No
local s = ""
for i = 1, 100000 do
    s = s .. "a"
end
```

```lua
--Yes
local new_tab = require "table.new"
local t = new_tab(100, 0)
for i = 1, 100000 do
    t[i] = "a"
end
local s = table.concat(t, "")
```

## Function

The naming of functions also follows `snake_case`:

```lua
--No
local function testNginx()
end
```

```lua
--Yes
local function test_nginx()
end
```

The function should return as early as possible:

```lua
--No
local function check(age, name)
    local ret = true
    if age < 20 then
        ret = false
    end

    if name == "a" then
        ret = false
    end
    -- do something else
    return ret
end
```

```lua
--Yes
local function check(age, name)
    if age < 20 then
        return false
    end

    if name == "a" then
        return false
    end
    -- do something else
    return true
end
```

## Module

All require libraries must be localized:

```lua
--No
local function foo()
    local ok, err = ngx.timer.at(delay, handler)
end
```

```lua
--Yes
local timer_at = ngx.timer.at

local function foo()
    local ok, err = timer_at(delay, handler)
end
```

For style unification, `require` and `ngx` also need to be localized:

```lua
--No
local core = require("apisix.core")
local timer_at = ngx.timer.at

local function foo()
    local ok, err = timer_at(delay, handler)
end
```

```lua
--Yes
local ngx = ngx
local require = require
local core = require("apisix.core")
local timer_at = ngx.timer.at

local function foo()
    local ok, err = timer_at(delay, handler)
end
```

## Error handling

For functions that return with error information, the error information must be judged and processed:

```lua
--No
local sock = ngx.socket.tcp()
local ok = sock:connect("www.google.com", 80)
ngx.say("successfully connected to google!")
```

```lua
--Yes
local sock = ngx.socket.tcp()
local ok, err = sock:connect("www.google.com", 80)
if not ok then
    ngx.say("failed to connect to google: ", err)
    return
end
ngx.say("successfully connected to google!")
```

The function you wrote yourself, the error message is to be returned as a second parameter in the form of a string:

```lua
--No
local function foo()
    local ok, err = func()
    if not ok then
        return false
    end
    return true
end
```

```lua
--No
local function foo()
    local ok, err = func()
    if not ok then
        return false, {msg = err}
    end
    return true
end
```

```lua
--Yes
local function foo()
    local ok, err = func()
    if not ok then
        return false, "failed to call func(): " .. err
    end
    return true
end
```
