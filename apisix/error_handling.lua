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
local core = require("apisix.core")
local ngx = ngx


local _M = {}
local page_500 = [[<!DOCTYPE html>
<html>
<head>
<meta content="text/html;charset=utf-8" http-equiv="Content-Type">
<meta content="utf-8" http-equiv="encoding">
<title>500 Internal Server Error</title>
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
</html>]]


function _M.handle_500()
    core.response.set_header("Content-Type", "text/html")
    ngx.say(page_500)
end


return _M
