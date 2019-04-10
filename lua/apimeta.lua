-- Copyright (C) Yuansheng Wang

local _M = {}

function _M.init()
    
end

function _M.init_worker()
    require("apimeta.router.load").init_worker()
end

function _M.access()
    ngx.say("hello")
end

function _M.header_filter()
    
end

function _M.log()
    
end

return _M
