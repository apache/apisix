-- apisix/plugins/ai-drivers/openai-base.lua (重构后)

local core = require("apisix.core")
local driver_base = require("apisix.plugins.ai-drivers.ai-driver-base")
local sse = require("apisix.plugins.ai-drivers.sse")

local _M = {}

-- OpenAI 驱动的构造函数
function _M.new(opts)
    -- 继承通用基类，并传入 OpenAI 的 API 信息和自定义处理函数
    local self = driver_base.new({
        host = opts.host,
        port = opts.port,
        path = opts.path,
        scheme = opts.scheme or "https",
        -- OpenAI 特有的处理函数
        process_sse_chunk = _M.process_sse_chunk,
        parse_token_usage = _M.parse_token_usage,
        -- transform_request 和 transform_response 在 OpenAI 兼容层中通常不需要
    } )

    return self
end

-- 将 OpenAI 原生流式响应块转换为 APISIX 兼容格式（主要用于 token 统计和错误处理）
function _M.process_sse_chunk(chunk)
    local events = sse.decode(chunk)
    local contents = {}

    for _, event in ipairs(events) do
        if event.type == "message" then
            local data, err = core.json.decode(event.data)
            if not data then
                core.log.warn("failed to decode SSE data: ", err)
                goto continue
            end

            -- 提取 token usage (仅在非流式或流式结束时出现)
            if data.usage and type(data.usage) == "table" then
                -- 实际 APISIX 实现中，这部分逻辑可能在 ai-proxy 插件的 response 阶段
                -- 这里仅作示意，实际应依赖 APISIX 内部机制
            end

            -- 提取内容
            if data.choices and type(data.choices) == "table" and #data.choices > 0 then
                for _, choice in ipairs(data.choices) do
                    if type(choice) == "table" and type(choice.delta) == "table" and type(choice.delta.content) == "string" then
                        table.insert(contents, choice.delta.content)
                    end
                end
            end
        end
        ::continue::
    end

    -- 返回原始 chunk，因为 OpenAI 兼容层不需要对 chunk 本身进行格式转换
    return chunk
end

-- 解析 OpenAI 的 token usage
function _M.parse_token_usage(openai_usage)
    if not openai_usage then
        return nil
    end

    return {
        prompt_tokens = openai_usage.prompt_tokens or 0,
        completion_tokens = openai_usage.completion_tokens or 0,
        total_tokens = openai_usage.total_tokens or 0
    }
end

return _M.new({})