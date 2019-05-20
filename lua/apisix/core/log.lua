-- Copyright (C) Yuansheng Wang

local ngx = ngx
local ngx_log  = ngx.log
local ngx_DEBUG= ngx.DEBUG
local DEBUG    = ngx.config.debug
-- todo: support stream module
local cur_level = ngx.config.subsystem == "http" and
                  require "ngx.errlog" .get_sys_filter_level()

local _M = {version = 0.1}


for name, log_level in pairs({stderr = ngx.STDERR,
                              emerg  = ngx.EMERG,
                              alert  = ngx.ALERT,
                              crit   = ngx.CRIT,
                              error  = ngx.ERR,
                              warn   = ngx.WARN,
                              notice = ngx.NOTICE,
                              info   = ngx.INFO, }) do
    _M[name] = function(...)
        if cur_level and log_level > cur_level then
            return
        end

        return ngx_log(log_level, ...)
    end
end


function _M.debug(...)
    if not DEBUG and cur_level and ngx_DEBUG > cur_level then
        return
    end

    return ngx_log(ngx_DEBUG, ...)
end


return _M
