-- apisix/plugins/ai-drivers/ai-driver-base.lua

local core = require("apisix.core")
local plugin = require("apisix.plugin")
local http = require("resty.http" )
local url = require("socket.url")
-- 假设 sse 模块存在于 apisix.plugins.ai-drivers.sse
local sse = require("apisix.plugins.ai-drivers.sse") 

local _M = {}
local mt = {
    __index = _M
}

-- 构造函数，用于初始化驱动的通用配置
function _M.new(opts)
    local self = {
        host = opts.host,
        port = opts.port,
        path = opts.path,
        scheme = opts.scheme or "https",
        -- 抽象方法占位符 ，由具体驱动实现
        transform_request = opts.transform_request,
        transform_response = opts.transform_response,
        process_sse_chunk = opts.process_sse_chunk,
        parse_token_usage = opts.parse_token_usage,
    }

    return setmetatable(self, mt)
end

-- 通用请求验证：检查 Content-Type 并解析 JSON
function _M.validate_request(self, ctx)
    local ct = core.request.header(ctx, "Content-Type")
    if not core.string.has_prefix(ct, "application/json") then
        return nil, "unsupported content-type: " .. ct .. ", only application/json is supported"
    end

    local request_table, err = core.request.get_json_request_body_table()
    if not request_table then
        return nil, err
    end

    return request_table, nil
end

-- 通用错误处理
function _M.handle_error(self, err)
    if core.string.find(err, "timeout") then
        return core.response.exit(504) -- HTTP_GATEWAY_TIMEOUT
    end
    return core.response.exit(500) -- HTTP_INTERNAL_SERVER_ERROR
end

-- 核心请求方法
function _M.request(self, ctx, conf, request_table, extra_opts)
    -- 1. 协议转换（如果驱动提供了 transform_request）
    if self.transform_request then
        request_table = self.transform_request(request_table)
    end

    -- 2. 构造上游请求
    local upstream_url = self.scheme .. "://" .. self.host .. ":" .. self.port .. self.path
    local headers = {
        ["Host"] = self.host,
        ["Content-Type"] = "application/json",
        -- 认证头由具体驱动在 transform_request 中添加或在 conf 中获取
    }

    -- 3. 发送请求
    local httpc = http.new( )
    local res, err = httpc:request({
        method = "POST",
        url = upstream_url,
        headers = headers,
        body = core.json.encode(request_table ),
        ssl_verify = false, -- 生产环境应为 true
        timeout = conf.timeout or 60000,
    })

    if not res then
        core.log.error("failed to send request to LLM server: ", err)
        return self:handle_error(err)
    end

    -- 4. 处理响应
    local is_stream = request_table.stream
    local content_type = res.headers["Content-Type"]

    if is_stream and core.string.find(content_type, "text/event-stream") then
        -- 流式响应处理
        return self:handle_stream_response(ctx, res, conf)
    else
        -- 非流式响应处理
        return self:handle_non_stream_response(ctx, res, conf)
    end
end

-- 处理非流式响应
function _M.handle_non_stream_response(self, ctx, res, conf)
    local raw_res_body = res:read_body()
    if not raw_res_body then
        core.log.warn("failed to read response body: ", res.err)
        return self:handle_error(res.err)
    end

    -- 协议转换（如果驱动提供了 transform_response）
    if self.transform_response then
        raw_res_body = self.transform_response(raw_res_body)
    end

    -- 设置响应头和状态码
    core.response.set_header(ctx, "Content-Type", "application/json")
    core.response.set_status(ctx, res.status)
    core.response.set_body(ctx, raw_res_body)
    core.response.send_response(ctx)
end

-- 处理流式响应
function _M.handle_stream_response(self, ctx, res, conf)
    core.response.set_header(ctx, "Content-Type", "text/event-stream")
    core.response.set_status(ctx, res.status)
    core.response.send_http_header(ctx )

    local body_reader = res.body_reader
    local chunk
    while true do
        chunk, err = body_reader()
        if not chunk then
            break
        end

        -- 协议转换（如果驱动提供了 process_sse_chunk）
        if self.process_sse_chunk then
            chunk = self.process_sse_chunk(chunk)
        end

        core.response.write(ctx, chunk)
    end

    if err then
        core.log.error("failed to read stream body: ", err)
    end

    core.response.close(ctx)
end

return _M