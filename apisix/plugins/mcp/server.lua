local setmetatable = setmetatable
local ngx          = ngx
local ngx_sleep    = ngx.sleep
local thread_spwan = ngx.thread.spawn
local thread_wait  = ngx.thread.wait
local thread_kill  = ngx.thread.kill
local core         = require("apisix.core")
local broker_utils = require("apisix.plugins.mcp.broker.utils")


local _M = {}
local mt = { __index = _M }


_M.EVENT_CLIENT_MESSAGE = "event:client_message"


-- TODO: ping requester and handler
function _M.new(opts)
    if opts.session_id then -- TODO: check if session_id is exists

    end

    local session_id = opts.session_id or core.id.gen_uuid_v4()

    -- TODO: configurable broker type
    local message_broker = require("apisix.plugins.mcp.broker.shared_dict").new({
        session_id = session_id,
    })

    -- TODO: configurable transport type
    local transport = require("apisix.plugins.mcp.transport.sse").new()

    local obj = setmetatable({
        opts = opts,
        session_id = session_id,
        next_ping_id = 0,
        transport = transport,
        message_broker = message_broker,
        event_handler = {},
        need_exit = false,
    }, mt)

    message_broker:on(broker_utils.EVENT_MESSAGE, function (message, additional)
        if obj.event_handler[_M.EVENT_CLIENT_MESSAGE] then
            obj.event_handler[_M.EVENT_CLIENT_MESSAGE](message, additional)
        end
    end)

    return obj
end


function _M.on(self, event, cb)
    self.event_handler[event] = cb
end


function _M.start(self)
    self.message_broker:start()

    -- ping loop
    local ping = thread_spwan(function()
        while true do
            if self.need_exit then
                break
            end

            self.next_ping_id = self.next_ping_id + 1
            local ok, err = self.transport:send(
                '{"jsonrpc": "2.0","method": "ping","id":"ping:' .. self.next_ping_id .. '"}')
            if not ok then
                core.log.info("session ", self.session_id,
                               " exit, failed to send ping message: ", err)
                self.need_exit = true
                break
            end
            ngx_sleep(30)
        end
    end)
    thread_wait(ping)
    thread_kill(ping)
end


function _M.close(self)
    if self.message_broker then
        self.message_broker:close()
    end
end


function _M.push_message(self, message)
    local ok, err = self.message_broker:push(message)
    if not ok then
        return nil, "failed to push message to broker: " .. err
    end
    return true
end


return _M
