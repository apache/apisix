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

[English](CODE_STYLE.md)

# APISIX Lua 编码风格指南

## 缩进

使用 4 个空格作为缩进的标记：

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

你可以在使用的编辑器中把 tab 改为 4 个空格来简化操作。

## 空格

在操作符的两边，都需要用一个空格来做分隔：

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

## 空行

不少开发者会在行尾增加一个分号：

```lua
--No
if a then
    ngx.say("hello");
end;
```

增加分号会让 Lua 代码显得非常丑陋，也是没有必要的。

另外，不要为了显得“简洁”节省代码行数，而把多行代码变为一行。这样会在定位错误的时候不知道到底哪一段代码出了问题：

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

函数之间需要用两个空行来做分隔：

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

如果有多个 if elseif 的分支，它们之间需要一个空行来做分隔：

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

## 每行最大长度

每行不能超过 80 个字符，超过的话，需要换行并对齐：

```lua
--No
return limit_conn_new("plugin-limit-conn", conf.conn, conf.burst, conf.default_conn_delay)
```

```lua
--Yes
return limit_conn_new("plugin-limit-conn", conf.conn, conf.burst,
                      conf.default_conn_delay)
```

在换行对齐的时候，要体现出上下两行的对应关系。

就上面示例而言，第二行函数的参数，要在第一行左括号的右边。

如果是字符串拼接的对齐，需要把 `..` 放到下一行中：

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
                 .. "plugin-limit-conn")
```

## 变量

应该永远使用局部变量，不要使用全局变量：

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

变量命名使用 `snake_case`（蛇形命名法） 风格:

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

对于常量要使用全部大写：

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

## 表格/数组

使用 `table.new` 来预先分配数组：

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

不要在数组中使用 `nil`：

```lua
--No
local t = {1, 2, nil, 3}
```

如果一定要使用空值，请用 `ngx.null` 来表示:

```lua
--Yes
local t = {1, 2, ngx.null, 3}
```

## 字符串

不要在热代码路径上拼接字符串：

```lua
--No
local s = ""
for i = 1, 100000 do
    s = s .. "a"
end
```

```lua
--Yes
local t = {}
for i = 1, 100000 do
    t[i] = "a"
end
local s = table.concat(t, "")
```

## 函数

函数的命名也同样遵循 `snake_case`（蛇形命名法）:

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

函数应该尽可能早的返回：

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

## 模块

所有 `require` 的库都要 `local` 化：

```lua

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

为了风格的统一，`require` 和 `ngx` 也需要 `local` 化:

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

## 错误处理

对于有错误信息返回的函数，必须对错误信息进行判断和处理：

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

自己编写的函数，错误信息要作为第二个参数，用字符串的格式返回：

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
