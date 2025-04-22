local ngx          = ngx
local ngx_exit     = ngx.exit
local re_match     = ngx.re.match
local core         = require("apisix.core")
local mcp_server   = require("apisix.plugins.mcp.server")

local _M = {}

local V241105_ENDPOINT_SSE     = "sse"
local V241105_ENDPOINT_MESSAGE = "message"


local function sse_handler(conf, ctx, opts)
    -- send SSE headers and first chunk
    core.response.set_header("Content-Type", "text/event-stream")
    core.response.set_header("Cache-Control", "no-cache")

    local server = opts.server

    -- send endpoint event to advertise the message endpoint
    server.transport:send(conf.base_uri .. "/message?sessionId=" .. server.session_id, "endpoint")

    if opts.event_handler and opts.event_handler.on_client_message then
        server:on(mcp_server.EVENT_CLIENT_MESSAGE, function(message, additional)
            additional.server = server
            opts.event_handler.on_client_message(message, additional)
        end)
    end

    if opts.event_handler and opts.event_handler.on_connect then
        local code, body = opts.event_handler.on_connect({ server = server })
        if code then
            return code, body
        end
        server:start() -- this is a sync call that only returns when the client disconnects
    end

    if opts.event_handler.on_disconnect then
        opts.event_handler.on_disconnect({ server = server })
        server:close()
    end

    ngx_exit(0) -- exit current phase, skip the upstream module
end


local function message_handler(conf, ctx, opts)
    local body = core.request.get_body(nil, ctx)
    if not body then
        return 400
    end

    local ok, err = opts.server:push_message(body)
    if not ok then
        core.log.error("failed to add task to queue: ", err)
        return 500
    end

    return 202
end


function _M.access(conf, ctx, opts)
    local m, err = re_match(ctx.var.uri, "^" .. conf.base_uri .. "/(.*)", "jo")
    if err then
        core.log.info("failed to mcp base uri: ", err)
        return core.response.exit(404)
    end
    local action = m and m[1] or false
    if not action then
        return core.response.exit(404)
    end

    if action == V241105_ENDPOINT_SSE and core.request.get_method() == "GET" then
        opts.server = mcp_server.new({})
        return sse_handler(conf, ctx, opts)
    end

    if action == V241105_ENDPOINT_MESSAGE and core.request.get_method() == "POST" then
        -- TODO: check ctx.var.arg_sessionId
        -- recover server instead of create
        opts.server = mcp_server.new({ session_id = ctx.var.arg_sessionId })
        return core.response.exit(message_handler(conf, ctx, opts))
    end

    return core.response.exit(404)
end


return _M
