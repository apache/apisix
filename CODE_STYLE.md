# Code Style of OpenResty

## indentation
Use 4 spaces as an indent in OpenResty, although Lua does not have such a grammar requirement.

```
--No
if a then
ngx.say("hello")
end
```

```
--yes
if a then
    ngx.say("hello")
end
```

You can simplify the operation by changing the tab to 4 spaces in the editor you are using.

## Space
On both sides of the operator, you need to use a space to separate:

```
--No
local i=1
local s    =    "apisix"
```

```
--Yes
local i = 1
local s = "apisix"
```

## Blank line
Many developers will bring the development habits of other languages to OpenResty, such as adding a semicolon at the end of the line.

```
--No
if a then
    ngx.say("hello");
end;
```

Adding a semicolon will make the Lua code look ugly and unnecessary. Also, don't want to save the number of lines in the code, the latter turns the multi-line code into one line in order to appear "simple". This will not know when the positioning error is in the end of the code:

```
--No
if a then ngx.say("hello") end
```

```
--yes
if a then
    ngx.say("hello")
end
```

The functions needs to be separated by two blank lines:
```
--No
local function foo()
end
local function bar()
end
```

```
--Yes
local function foo()
end


local function bar()
end
```

If there are multiple if elseif branches, they need a blank line to separate them:
```
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

```
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
Each line cannot exceed 80 characters. If it exceeds, you need to wrap and align:

```
--No
return limit_conn_new("plugin-limit-conn", conf.conn, conf.burst, conf.default_conn_delay)
```

```
--Yes
return limit_conn_new("plugin-limit-conn", conf.conn, conf.burst,
                      conf.default_conn_delay)
```

When the linefeed is aligned, the correspondence between the upper and lower lines should be reflected. For the example above, the parameters of the second line of functions are to the right of the left parenthesis of the first line.

If it is a string stitching alignment, you need to put `..` in the next line:
```
--No
return limit_conn_new("plugin-limit-conn" ..  "plugin-limit-conn" ..
                      "plugin-limit-conn")
```

```
--Yes
return limit_conn_new("plugin-limit-conn" .. "plugin-limit-conn"
                      .. "plugin-limit-conn")
```

## Variable
Local variables should always be used, not global variables:
```
--No
i = 1
s = "apisix"
```

```
--Yes
local i = 1
local s = "apisix"
```

Variable naming uses the `snake_case` style:
```
--No
local IndexArr = 1
local str_Name = "apisix"
```

```
--Yes
local index_arr = 1
local str_name = "apisix"
```

Use all capitalization for constants:
```
--No
local max_int = 65535
local server_name = "apisix"
```

```
--Yes
local MAX_INT = 65535
local SERVER_NAME = "apisix"
```

## Table
Use `table.new` to pre-allocate the table:
```
--No
local t = {}
for i = 1, 100 do
    t[i] = i
end
```

```
--Yes
local new_tab = require "table.new"
local t = new_tab(100, 0)
for i = 1, 100 do
    t[i] = i
end
```

Don't use `nil` in an array:
```
--No
local t = {1, 2, nil, 3}
```

If you must use null values, use `ngx.null` to indicate:
```
--No
local t = {1, 2, ngx.null, 3}
```

## String
Do not splicing strings on the hot code path:
```
--No
local s = ""
for i = 1, 100000 do
    s = s .. "a"
end
```

```
--Yes
local t = {}
for i = 1, 100000 do
    t[i] = "a"
end
local s = table.concat(t, "")
```

## Function
The naming of functions also follows `snake_case`:
```
--No
local function testNginx()
end
```

```
--Yes
local function test_nginx()
end
```

The function should return as early as possible:
```
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

```
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
```
--No
local function foo()
    local ok, err = ngx.timer.at(delay, handler)
end
```

```
--Yes
local timer_at = ngx.timer.at

local function foo()
    local ok, err = timer_at(delay, handler)
end
```

For style unification, `require` and `ngx` also need to be localized:
```
--No
local core = require("apisix.core")
local timer_at = ngx.timer.at

local function foo()
    local ok, err = timer_at(delay, handler)
end
```

```
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
```
--No
local sock = ngx.socket.tcp()
local ok = sock:connect("www.google.com", 80)
ngx.say("successfully connected to google!")
```

```
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
```
--No
local function foo()
    local ok, err = func()
    if not ok then
        return false
    end
    return true
end
```

```
--No
local function foo()
    local ok, err = func()
    if not ok then
        return false, {msg = err}
    end
    return true
end
```

```
--Yes
local function foo()
    local ok, err = func()
    if not ok then
        return false, "failed to call func(): " .. err
    end
    return true
end
```
