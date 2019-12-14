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
local ngx_log  = ngx.log
local ngx_DEBUG= ngx.DEBUG
local DEBUG    = ngx.config.debug
local require  = require


local _M = {version = 0.3}


local log_levels = {
    stderr = ngx.STDERR,
    emerg  = ngx.EMERG,
    alert  = ngx.ALERT,
    crit   = ngx.CRIT,
    error  = ngx.ERR,
    warn   = ngx.WARN,
    notice = ngx.NOTICE,
    info   = ngx.INFO
}


do
    local cur_level

function _M.debug(...)
    if not cur_level then
        cur_level = ngx.config.subsystem == "http" and
                        require "ngx.errlog" .get_sys_filter_level()
    end

    if not DEBUG and cur_level and ngx_DEBUG > cur_level then
        return
    end

    return ngx_log(ngx_DEBUG, ...)
end

end -- do


setmetatable(_M, {__index = function(self, cmd)
    local cur_level = ngx.config.subsystem == "http" and
                        require "ngx.errlog" .get_sys_filter_level()
    local log_level = log_levels[cmd]

    local method
    if cur_level and log_levels[cmd] > cur_level then
        method = function() end
    else
        method = function(...)
            return ngx_log(log_level, ...)
        end
    end

    -- cache the lazily generated method in our
    -- module table
    _M[cmd] = method
    return method
end})


return _M
