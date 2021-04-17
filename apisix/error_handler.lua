--
-- Licensed to the Apache Software Foundation (ASF) under one or more
-- contributor license agreements.  See the NOTICE file distributed with
-- this work for additional information regarding copyright ownership.
-- The ASF licenses this file to You under the Apache License, Version 2.0
-- (the "License"); you may not use this file except in compliance with
-- the License.  You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--
local ngx = ngx
local str_format = string.format


local html_5xx = [[
<!DOCTYPE html>
<html>
<head>
<meta content="text/html;charset=utf-8" http-equiv="Content-Type">
<meta content="utf-8" http-equiv="encoding">
<title>Error</title>
<style>
    body {
        width: 35em;
        margin: 0 auto;
        font-family: Tahoma, Verdana, Arial, sans-serif;
    }
</style>
</head>
<body>
<h1>An error occurred.</h1>
<p>You can report issue to <a href="https://github.com/apache/apisix/issues">APISIX</a></p>
<p><em>Faithfully yours, <a href="https://apisix.apache.org/">APISIX</a>.</em></p>
</body>
</html>
]]

local html_4xx = [[
<html>
<head><title>%s</title></head>
<body>
<center><h1>%s</h1></center>
<hr><center> <a href="https://apisix.apache.org/">APISIX</a></center>
</body>
</html>
]]

local ngx_status_line = {
    [400] = "400 Bad Request",
    [401] = "401 Unauthorized",
    [403] = "403 Forbidden",
    [404] = "404 Not Found",
    [405] = "405 Not Allowed",
}

local _M = {}
_M.error_page = function()
    ngx.header.content_type = "text/html; charset=utf-8"
    if ngx.status >= 500 and ngx.status <= 599 then
        ngx.say(html_5xx)
    end

    if ngx.status >= 400 and ngx.status <= 499 then
        local status_line = ngx_status_line[ngx.status] or ""
        local resp = str_format(html_4xx, status_line, status_line)
        ngx.say(resp)
    end
end

return _M

