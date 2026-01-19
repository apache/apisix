local core = require("apisix.core")
local driver_base = require("apisix.plugins.ai-drivers.ai-driver-base")
local sse = require("apisix.plugins.ai-drivers.sse")

local _M = {}

-- 将 OpenAI 兼容请求转换为 Anthropic 原生请求
function _M.transform_request(request_table)
    local anthropic_request = {
        model = request_table.model,
        max_tokens = request_table.max_tokens or 1024,
        stream = request_table.stream,
    }

    local messages = request_table.messages
    local system_prompt = nil
    local new_messages = {}

    for _, msg in ipairs(messages) do
        if msg.role == "system" then
            -- Anthropic Messages API 支持 system 字段
            system_prompt = msg.content
        elseif msg.role == "user" or msg.role == "assistant" then
            -- 角色映射：OpenAI 的 user/assistant 对应 Anthropic 的 user/assistant
            table.insert(new_messages, {
                role = msg.role,
                content = msg.content
            })
        end
    end

    if system_prompt then
        anthropic_request.system = system_prompt
    end

    anthropic_request.messages = new_messages

    -- 【添加日志打印】在返回前打印转换后的请求体，方便我们验证逻辑
    local core = require("apisix.core")
    core.log.warn("--- 转换后的 Anthropic 请求体开始 ---")
    core.log.warn(core.json.encode(anthropic_request))
    core.log.warn("--- 转换后的 Anthropic 请求体结束 ---")

    return anthropic_request
end

-- 处理流式响应的 SSE Chunk 转换
function _M.process_sse_chunk(chunk)
    local events = sse.decode(chunk)
    local out = {}

    for _, e in ipairs(events) do
        if e.type == "message" then
            local d = core.json.decode(e.data)
            if d.type == "content_block_delta" then
                -- 转换为 OpenAI 兼容的流式格式
                table.insert(out, "data: " .. core.json.encode({
                    choices = {
                        {
                            delta = {
                                content = d.delta.text
                            }
                        }
                    }
                }) .. "\n")
            elseif d.type == "message_stop" then
                table.insert(out, "data: [DONE]\n")
            end
        end
    end

    return table.concat(out)
end

-- 将 Anthropic 原生响应转换为 OpenAI 兼容响应
function _M.transform_response(body)
    local d = core.json.decode(body)
    return core.json.encode({
        choices = {
            {
                message = {
                    content = d.content[1].text
                }
            }
        }
    })
end

-- 导出驱动实例
return driver_base.new({
    host = "api.anthropic.com",
    port = 443,
    path = "/v1/messages",
    transform_request = _M.transform_request,
    transform_response = _M.transform_response,
    process_sse_chunk = _M.process_sse_chunk
})
