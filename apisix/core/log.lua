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
local require  = require
local select = select
local setmetatable = setmetatable
local tostring = tostring
local unpack = unpack
-- avoid loading other module since core.log is the most foundational one
local tab_clear = require("table.clear")


local _M = {version = 0.4}


local log_levels = {
    stderr = ngx.STDERR,
    emerg  = ngx.EMERG,
    alert  = ngx.ALERT,
    crit   = ngx.CRIT,
    error  = ngx.ERR,
    warn   = ngx.WARN,
    notice = ngx.NOTICE,
    info   = ngx.INFO,
    debug  = ngx.DEBUG,
}


local cur_level = ngx.config.subsystem == "http" and
                  require "ngx.errlog" .get_sys_filter_level()
local do_nothing = function() end


function _M.new(prefix)
    local m = {version = _M.version}
    setmetatable(m, {__index = function(self, cmd)
        local log_level = log_levels[cmd]

        local method
        if cur_level and (log_level > cur_level)
        then
            method = do_nothing
        else
            method = function(...)
                return ngx_log(log_level, prefix, ...)
            end
        end

        -- cache the lazily generated method in our
        -- module table
        m[cmd] = method
        return method
    end})

    return m
end


setmetatable(_M, {__index = function(self, cmd)
    local log_level = log_levels[cmd]

    local method
    if cur_level and (log_level > cur_level)
    then
        method = do_nothing
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


local delay_tab = setmetatable({
    func = function() end,
    args = {},
    res = nil,
    }, {
    __tostring = function(self)
        -- the `__tostring` will be called twice, the first to get the length and
        -- the second to get the data
        if self.res then
            local res = self.res
            -- avoid unexpected reference
            self.res = nil
            return res
        end

        local res, err = self.func(unpack(self.args))
        if err then
            ngx.log(ngx.WARN, "failed to exec: ", err)
        end

        -- avoid unexpected reference
        tab_clear(self.args)
        self.res = tostring(res)
        return self.res
    end
})


-- It works well with log.$level, eg: log.info(..., log.delay_exec(func, ...))
-- Should not use it elsewhere.
function _M.delay_exec(func, ...)
    delay_tab.func = func

    tab_clear(delay_tab.args)
    for i = 1, select('#', ...) do
        delay_tab.args[i] = select(i, ...)
    end

    delay_tab.res = nil
    return delay_tab
end


return _M
