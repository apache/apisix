--
-- Licensed to the Apache Software Foundation (ASF) under one or more
-- contributor license agreements.  See the NOTICE file distributed with
-- this work for additional information regarding copyright ownership.
-- The ASF licenses this file to You under the Apache License, Version 2.0
-- (the "License"); you may not use this file except in compliance with
-- the License.  You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--

--- ai-peyeeye: PII redaction & rehydration via the peyeeye.ai API.
--
-- On request the plugin extracts every text-bearing chunk from the
-- request body, sends them in a single batch to peyeeye's /v1/redact,
-- swaps the redacted text back into the request before it reaches the
-- LLM, and records the session id on the request context.
--
-- On response the plugin reads the model's text, sends it to /v1/rehydrate
-- so placeholders are swapped back to the originals, replaces the response
-- payload, and best-effort DELETEs the session.
--
-- Behavioral invariants (no silent PII passthrough):
--
--   * If /v1/redact returns a different number of texts than were sent,
--     or returns an unexpected response shape, access() fails closed
--     (HTTP 500) — the unredacted text is never forwarded upstream.
--   * If the api_key is missing the plugin refuses to load.
--   * Rehydrate failures fall back to the model's redacted output rather
--     than leaking PII.
--
-- This plugin is designed to be paired with ai-proxy / ai-proxy-multi
-- (the same way ai-aliyun-content-moderation is); it relies on the AI
-- proxy flow to invoke lua_body_filter for response rehydration.

local core      = require("apisix.core")
local protocols = require("apisix.plugins.ai-protocols")
local http      = require("resty.http")
local url       = require("socket.url")

local ngx       = ngx
local ngx_ok    = ngx.OK
local ipairs    = ipairs
local pairs     = pairs
local type      = type
local tostring  = tostring
local table     = table
local string    = string
local os        = os

local plugin_name = "ai-peyeeye"

local DEFAULT_API_BASE = "https://api.peyeeye.ai"


local schema = {
    type = "object",
    properties = {
        api_key = {
            type = "string",
            minLength = 1,
            description = "peyeeye API key (Bearer). Falls back to env PEYEEYE_API_KEY.",
        },
        api_base = {
            type = "string",
            minLength = 1,
            default = DEFAULT_API_BASE,
            description = "peyeeye API base URL. Defaults to https://api.peyeeye.ai.",
        },
        locale = {
            type = "string",
            default = "auto",
            description = "BCP-47 locale hint passed to /v1/redact. Defaults to 'auto'.",
        },
        entities = {
            type = "array",
            items = { type = "string", minLength = 1 },
            description = "Optional whitelist of peyeeye entity ids to detect. " ..
                          "When omitted the server uses its default set.",
        },
        session_mode = {
            type = "string",
            enum = { "stateful", "stateless" },
            default = "stateful",
            description = "stateful: peyeeye retains the token->value map under a ses_… id. " ..
                          "stateless: peyeeye returns a sealed skey_… blob and retains nothing.",
        },
        timeout = {
            type = "integer",
            minimum = 1,
            default = 15000,
            description = "HTTP timeout in milliseconds for calls to the peyeeye API.",
        },
        keepalive = { type = "boolean", default = true },
        keepalive_pool = { type = "integer", minimum = 1, default = 30 },
        keepalive_timeout = { type = "integer", minimum = 1000, default = 60000 },
        ssl_verify = { type = "boolean", default = true },
    },
    encrypt_fields = { "api_key" },
}


local _M = {
    version  = 0.1,
    -- Higher than ai-proxy (1040) and ai-aliyun-content-moderation (1029) so
    -- redaction happens before the request reaches the AI provider.
    priority = 1074,
    name     = plugin_name,
    schema   = schema,
}


function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    if not conf.api_key or conf.api_key == "" then
        local from_env = os.getenv("PEYEEYE_API_KEY")
        if not from_env or from_env == "" then
            return false, "ai-peyeeye: api_key is required " ..
                          "(set in plugin config or via PEYEEYE_API_KEY env var)"
        end
    end

    return true
end


-- ----------------------------------------------------------------- internals

local function resolve_api_key(conf)
    if conf.api_key and conf.api_key ~= "" then
        return conf.api_key
    end
    return os.getenv("PEYEEYE_API_KEY")
end


local function resolve_api_base(conf)
    local base = conf.api_base
    if not base or base == "" then
        base = os.getenv("PEYEEYE_API_BASE") or DEFAULT_API_BASE
    end
    -- strip trailing slash to keep path concatenation predictable.
    if string.sub(base, -1) == "/" then
        base = string.sub(base, 1, -2)
    end
    return base
end


local function build_headers(conf)
    return {
        ["Authorization"] = "Bearer " .. resolve_api_key(conf),
        ["Content-Type"]  = "application/json",
        ["Accept"]        = "application/json",
        ["User-Agent"]    = "apisix-ai-peyeeye/0.1",
    }
end


local function peyeeye_request(conf, method, path, body_tab)
    local api_base = resolve_api_base(conf)
    local full = api_base .. path

    local parsed = url.parse(full)
    if not parsed or not parsed.host then
        return nil, "invalid api_base: " .. tostring(api_base)
    end

    local httpc = http.new()
    httpc:set_timeout(conf.timeout)

    local connect_opts = {
        scheme = parsed.scheme or "https",
        host = parsed.host,
        port = tonumber(parsed.port) or (parsed.scheme == "http" and 80 or 443),
        ssl_verify = conf.ssl_verify,
        ssl_server_name = parsed.host,
        pool_size = conf.keepalive and conf.keepalive_pool or nil,
    }
    local ok, err = httpc:connect(connect_opts)
    if not ok then
        return nil, "failed to connect to peyeeye: " .. err
    end

    local req = {
        method = method,
        path = parsed.path or path,
        headers = build_headers(conf),
    }
    if parsed.query and parsed.query ~= "" then
        req.path = req.path .. "?" .. parsed.query
    end
    if body_tab ~= nil then
        local encoded, encode_err = core.json.encode(body_tab)
        if not encoded then
            return nil, "failed to encode peyeeye request body: " .. tostring(encode_err)
        end
        req.body = encoded
    end

    local res, req_err = httpc:request(req)
    if not res then
        return nil, "failed to call peyeeye " .. path .. ": " .. tostring(req_err)
    end

    local raw, read_err = res:read_body()
    if not raw then
        return nil, "failed to read peyeeye response body: " .. tostring(read_err)
    end

    if conf.keepalive then
        local _, ka_err = httpc:set_keepalive(conf.keepalive_timeout, conf.keepalive_pool)
        if ka_err then
            core.log.warn("peyeeye: keepalive failed: ", ka_err)
        end
    else
        httpc:close()
    end

    if res.status == 401 or res.status == 403 then
        return nil, "peyeeye " .. path .. " auth failed (status " .. res.status .. ")"
    end
    if res.status >= 400 then
        return nil, "peyeeye " .. path .. " returned status " .. res.status ..
                    ", body: " .. tostring(raw)
    end

    if not raw or raw == "" then
        return {}
    end

    local decoded, decode_err = core.json.decode(raw)
    if decoded == nil then
        return nil, "failed to decode peyeeye response: " .. tostring(decode_err)
    end
    return decoded
end


-- Walk every text-bearing chunk in an OpenAI-chat-style messages list and
-- yield (msg_index, "content"|int, text). The integer is an index into the
-- multimodal content array; "content" means the content field is a string.
local function collect_message_texts(messages)
    local out = {}
    if type(messages) ~= "table" then
        return out
    end
    for i, msg in ipairs(messages) do
        if type(msg) == "table" then
            local content = msg.content
            if type(content) == "string" and content ~= "" then
                table.insert(out, { msg_index = i, part = "content", text = content })
            elseif type(content) == "table" then
                for j, part in ipairs(content) do
                    if type(part) == "table" and part.type == "text"
                            and type(part.text) == "string" and part.text ~= "" then
                        table.insert(out, { msg_index = i, part = j, text = part.text })
                    end
                end
            end
        end
    end
    return out
end


local function set_message_text(messages, slot, value)
    local msg = messages[slot.msg_index]
    if type(msg) ~= "table" then
        return
    end
    if slot.part == "content" then
        msg.content = value
        return
    end
    local parts = msg.content
    if type(parts) == "table" and type(slot.part) == "number" then
        local part = parts[slot.part]
        if type(part) == "table" then
            part.text = value
        end
    end
end


-- Some non-chat protocols (openai-responses, embeddings) place the
-- prompt in fields other than messages[]. To stay framework-aligned
-- and avoid silent passthrough we only redact protocols that expose a
-- messages[] array. For everything else we fall back to extract_request_content
-- and refuse the request rather than leaking PII.
local SUPPORTED_FOR_REWRITE = {
    ["openai-chat"] = true,
    ["anthropic-messages"] = true,
}


local function build_redact_body(conf, texts)
    local body = {
        text = texts,
        locale = conf.locale or "auto",
    }
    if conf.entities and #conf.entities > 0 then
        local copy = {}
        for i, e in ipairs(conf.entities) do
            copy[i] = e
        end
        body.entities = copy
    end
    if conf.session_mode == "stateless" then
        body.session = "stateless"
    end
    return body
end


local function extract_session(conf, payload)
    if type(payload) ~= "table" then
        return nil
    end
    if conf.session_mode == "stateless" then
        return payload.rehydration_key
    end
    return payload.session_id or payload.session
end


-- ----------------------------------------------------------------- access

function _M.access(conf, ctx)
    local body, err = core.request.get_body()
    if not body or body == "" then
        if err then
            core.log.warn("ai-peyeeye: failed to read request body: ", err)
        end
        return
    end

    local body_tab, decode_err = core.json.decode(body)
    if not body_tab then
        core.log.warn("ai-peyeeye: failed to decode request body as JSON: ", decode_err)
        return
    end

    local proto_name, detect_err = protocols.detect(body_tab, ctx)
    if not proto_name then
        core.log.info("ai-peyeeye: skipping (no AI protocol matched: ", detect_err or "", ")")
        return
    end

    if not SUPPORTED_FOR_REWRITE[proto_name] then
        return 500, { message = "ai-peyeeye: protocol '" .. proto_name ..
            "' is not yet supported for redaction; refusing to forward unredacted text" }
    end

    local messages = body_tab.messages
    local slots = collect_message_texts(messages)
    if #slots == 0 then
        return
    end

    local texts = {}
    for i, slot in ipairs(slots) do
        texts[i] = slot.text
    end

    local payload, post_err = peyeeye_request(conf, "POST", "/v1/redact",
                                              build_redact_body(conf, texts))
    if not payload then
        core.log.error("ai-peyeeye: /v1/redact failed: ", post_err)
        return 500, { message = "ai-peyeeye: redact call failed; " ..
                                "refusing to forward unredacted text" }
    end

    local redacted = payload.text
    if type(redacted) ~= "table" then
        core.log.error("ai-peyeeye: /v1/redact returned unexpected shape (text not array)")
        return 500, { message = "ai-peyeeye: redact returned unexpected response shape; " ..
                                "refusing to forward unredacted text" }
    end
    if #redacted ~= #slots then
        core.log.error("ai-peyeeye: /v1/redact returned ", #redacted,
                       " texts for ", #slots, " inputs")
        return 500, { message = "ai-peyeeye: redact returned mismatched text count; " ..
                                "refusing to forward unredacted text" }
    end

    for i, slot in ipairs(slots) do
        local out = redacted[i]
        if type(out) ~= "string" then
            core.log.error("ai-peyeeye: /v1/redact item ", i, " is not a string")
            return 500, { message = "ai-peyeeye: redact returned non-string entry; " ..
                                    "refusing to forward unredacted text" }
        end
        set_message_text(messages, slot, out)
    end

    local new_body, encode_err = core.json.encode(body_tab)
    if not new_body then
        core.log.error("ai-peyeeye: failed to re-encode request body: ", encode_err)
        return 500, { message = "ai-peyeeye: failed to re-encode redacted body" }
    end
    ngx.req.set_body_data(new_body)

    local session_id = extract_session(conf, payload)
    if session_id and session_id ~= "" then
        ctx.peyeeye_session_id = session_id
        ctx.peyeeye_session_mode = conf.session_mode
        ctx.peyeeye_redacted_count = #slots
    else
        core.log.info("ai-peyeeye: redact returned no session id; rehydration disabled")
    end
end


-- ----------------------------------------------------------------- response

local function rehydrate_text(conf, text, session_id)
    if not text or text == "" then
        return text
    end
    local payload, err = peyeeye_request(conf, "POST", "/v1/rehydrate", {
        text = text,
        session = session_id,
    })
    if not payload then
        core.log.warn("ai-peyeeye: /v1/rehydrate failed: ", err)
        return text
    end
    local out = payload.text
    if type(out) == "string" then
        return out
    end
    core.log.warn("ai-peyeeye: /v1/rehydrate returned unexpected shape; " ..
                  "leaving response as-is")
    return text
end


local function delete_session(conf, session_id)
    -- DELETE only applies to stateful sessions. Stateless skey_ blobs have no
    -- server-side state to release.
    if not session_id or session_id == "" then
        return
    end
    if string.sub(session_id, 1, 4) ~= "ses_" then
        return
    end
    local _, err = peyeeye_request(conf, "DELETE",
                                   "/v1/sessions/" .. session_id, nil)
    if err then
        core.log.warn("ai-peyeeye: best-effort session delete failed: ", err)
    end
end


-- Replace OpenAI-chat-style choices[].message.content (and multimodal text
-- parts) in-place. Returns the modified body or nil on no-op.
local function rehydrate_chat_body(conf, decoded, session_id)
    local touched = false
    if type(decoded) ~= "table" then
        return nil, touched
    end
    local choices = decoded.choices
    if type(choices) ~= "table" then
        return nil, touched
    end
    for _, choice in ipairs(choices) do
        if type(choice) == "table" and type(choice.message) == "table" then
            local content = choice.message.content
            if type(content) == "string" and content ~= "" then
                choice.message.content = rehydrate_text(conf, content, session_id)
                touched = true
            elseif type(content) == "table" then
                for _, part in ipairs(content) do
                    if type(part) == "table" and part.type == "text"
                            and type(part.text) == "string" and part.text ~= "" then
                        part.text = rehydrate_text(conf, part.text, session_id)
                        touched = true
                    end
                end
            end
        end
    end
    return decoded, touched
end


function _M.lua_body_filter(conf, ctx, headers, body)
    local session_id = ctx.peyeeye_session_id
    if not session_id then
        return
    end

    -- Don't try to rehydrate upstream errors.
    if ngx.status >= 400 then
        ctx.peyeeye_session_id = nil
        return
    end

    if type(body) ~= "string" or body == "" then
        return
    end

    local decoded, decode_err = core.json.decode(body)
    if not decoded then
        core.log.warn("ai-peyeeye: failed to decode response body for rehydration: ",
                      decode_err)
        return
    end

    local new_decoded, touched = rehydrate_chat_body(conf, decoded, session_id)
    if not touched or not new_decoded then
        return
    end

    local new_raw, encode_err = core.json.encode(new_decoded)
    if not new_raw then
        core.log.warn("ai-peyeeye: failed to re-encode rehydrated body: ", encode_err)
        return
    end

    -- Best-effort cleanup of the stateful session. Done after rehydrate so a
    -- failure here can never leak placeholders into the client response.
    if ctx.peyeeye_session_mode == "stateful" then
        delete_session(conf, session_id)
    end
    ctx.peyeeye_session_id = nil

    return ngx_ok, new_raw
end


-- Suppress unused-warnings for ipairs/pairs in some lua-check configs.
local _ = pairs

return _M
