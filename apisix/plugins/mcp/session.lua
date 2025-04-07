local table_insert = table.insert
local shared_dict = ngx.shared["mcp-session"]
local core = require("apisix.core")

local _M = {}
local mt = { __index = _M }

_M.STATE_UNINITIALIZED = "uninitialized"
_M.STATE_INITIALIZED = "initialized"

local function gen_session_id()
    return core.id.gen_uuid_v4()
end


function _M.new()
    local session = setmetatable({
        id = gen_session_id(),
        requests = {},
        responses = {},
        queue = {},
        state = _M.STATE_UNINITIALIZED,

        ping_id = 0,
        last_active_at = ngx.time(),
    }, mt)
    session:flush_to_storage()
    return session
end

-- for state machine
function _M.session_initialize(self, params)
    self.protocol_version = params.protocolVersion
    self.client_info = params.clientInfo
    self.capabilities = params.capabilities
    self.state = _M.STATE_INITIALIZED
    return self:flush_to_storage()
end


function _M.session_pong(self)
    self.last_active_at = ngx.time()
    return self:flush_to_storage()
end


function _M.push_message_queue(self, task)
    return shared_dict:rpush(self.id..":queue", task)
end


function _M.pop_message_queue(self)
    return shared_dict:lpop(self.id..":queue")
end


function _M.flush_to_storage(self)
    return shared_dict:set(self.id, core.json.encode(self))
end


function _M.destroy(self)
    return shared_dict:delete(self.id)
end


function _M.recover(session_id)
    local session, err = shared_dict:get(session_id)
    if not session then
        return nil, err
    end
    return setmetatable(core.json.decode(session), mt)
end


return _M
