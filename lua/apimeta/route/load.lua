-- Copyright (C) Yuansheng Wang

local ngx = ngx
local pcall = pcall
local apimeta = require("apimeta")
local log = apimeta.log


local _M = {version = 0.1}


local function load()

end


do
    local running

function _M.load(premature)
    if premature or running then
        return
    end

    running = true
    local ok, err = pcall(load)
    running = false

    if not ok then
        log.error("failed to call `load` function: ", err)
    end
end

end -- do


function _M.init_worker()
    ngx.timer.every(1, _M.load)
end


return _M
