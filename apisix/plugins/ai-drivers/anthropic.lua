-- 模块依赖
-- Module dependencies
local core = require("apisix.core")
local json = require("apisix.core.json")
local ai_driver_base = require("apisix.plugins.ai-drivers.ai-driver-base")

-- Module table and metatable inheriting from the generic AI driver base
-- 模块表和元表，继承自通用 AI 驱动基类
local _M = {}
local mt = { __index = setmetatable(_M, { __index = ai_driver_base }) }

-- Create a new Anthropic driver instance
-- 创建一个新的 Anthropic 驱动实例
function _M.new(opts)
    local self = ai_driver_base.new(opts)
    return setmetatable(self, mt)
end

-- Transform OpenAI format request to Anthropic format
-- 将 OpenAI 请求格式转换为 Anthropic 请求格式
-- Notes:
-- - Combines all `system` messages into `system` prompt for Anthropic.
-- - Preserves `user` and `assistant` messages in `messages` array.
-- 说明：
-- - 将所有 `system` 消息合并为 Anthropic 的 `system` 字段。
-- - 将 `user` 和 `assistant` 留作消息数组中的条目。
function _M.transform_request(self, openai_body)
    local anthropic_body = {
        model = openai_body.model,
        max_tokens = openai_body.max_tokens or 4096,
        stream = openai_body.stream,
        messages = {}
    }

    -- Aggregate system prompts into a single string
    -- 将 system 提示聚合为单个字符串
    local system_prompt = ""
    for _, msg in ipairs(openai_body.messages) do
        if msg.role == "system" then
            system_prompt = system_prompt .. msg.content
        else
            -- Map 'assistant' and 'user' roles directly
            -- 直接映射 'assistant' 和 'user' 角色
            table.insert(anthropic_body.messages, {
                role = msg.role,
                content = msg.content
            })
        end
    end

    if system_prompt ~= "" then
        anthropic_body.system = system_prompt
    end

    return anthropic_body
end

-- Transform Anthropic response to OpenAI format
-- 将 Anthropic 响应转换为 OpenAI 格式
-- Notes:
-- - Decodes Anthropic response body and maps fields to OpenAI-like structure.
-- - Assumes `body.content` is an array where first element contains `text`.
-- 说明：
-- - 解码 Anthropic 响应并将字段映射为类 OpenAI 的结构。
-- - 假定 `body.content` 为数组，首元素包含 `text`。
function _M.transform_response(self, anthropic_res)
    local body = json.decode(anthropic_res.body)
    if not body then
        return nil, "failed to decode response"
    end

    return {
        id = body.id,
        object = "chat.completion",
        created = os.time(),
        model = body.model,
        choices = {
            {
                index = 0,
                message = {
                    role = "assistant",
                    content = body.content[1].text
                },
                finish_reason = body.stop_reason
            }
        },
        usage = {
            prompt_tokens = body.usage.input_tokens,
            completion_tokens = body.usage.output_tokens,
            total_tokens = body.usage.input_tokens + body.usage.output_tokens
        }
    }
end

return _M
