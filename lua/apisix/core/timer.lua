-- Copyright (C) Yuansheng Wang

local log = require("apisix.core.log")
local sleep = ngx.sleep
local timer_every = ngx.timer.every
local update_time = ngx.update_time
local now = ngx.now
local pcall = pcall


local _M = {
    version = 0.1,
}


local function _internal(timer)
    timer.start_time = now()

    repeat
        local ok, err = pcall(timer.callback_fun)
        if not ok then
            log.error("failed to run the timer: ", timer.name, " err: ", err)
            sleep(timer.sleep_fail)

        elseif timer.sleep_succ > 0 then
            sleep(timer.sleep_succ)
        end

        update_time()
    until timer.each_ttl and now() >= timer.start_time + timer.each_ttl
end

local function run_timer(premature, self)
    if self.running or premature then
        return
    end

    self.running = true

    local ok, err = pcall(_internal, self)
    if not ok then
        log.error("failed to run timer[", self.name, "] err: ", err)
    end

    self.running = false
end


function _M.new(name, callback_fun, opts)
    if not name then
        return nil, "missing argument: name"
    end

    if not callback_fun then
        return nil, "missing argument: callback_fun"
    end

    opts = opts or {}
    local timer = {
        name       = name,
        each_ttl   = opts.each_ttl or 1,
        sleep_succ = opts.sleep_succ or 1,
        sleep_fail = opts.sleep_fail or 5,
        start_time = 0,

        callback_fun = callback_fun,
        running = false,
    }

    local hdl, err = timer_every(opts.check_interval or 1,
                                 run_timer, timer)
    if not hdl then
        return nil, err
    end

    return timer
end


return _M
