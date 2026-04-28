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

--- ai-pii-sanitizer: regex + Unicode-based PII scrubbing for LLM traffic.
-- See docs/en/latest/plugins/ai-pii-sanitizer.md for usage.

local core       = require("apisix.core")
local protocols  = require("apisix.plugins.ai-protocols")
local sse        = require("apisix.plugins.ai-transport.sse")
local unicode    = require("apisix.plugins.ai-security.unicode")
local patterns   = require("apisix.plugins.ai-pii-sanitizer.patterns")

local ngx        = ngx
local re_compile = require("resty.core.regex").re_match_compile
local re_gsub    = ngx.re.gsub
local str_sub    = string.sub
local str_fmt    = string.format
local tbl_concat = table.concat
local tbl_insert = table.insert
local ipairs     = ipairs
local pairs      = pairs
local type       = type
local tostring   = tostring

local plugin_name = "ai-pii-sanitizer"


local category_entry_schema = {
    oneOf = {
        { type = "string" },
        {
            type = "object",
            properties = {
                name       = { type = "string" },
                action     = { type = "string", enum = { "mask", "redact", "block", "alert" } },
                mask_style = { type = "string", enum = { "tag", "tag_flat", "partial", "hash" } },
            },
            required = { "name" },
        },
    },
}

local custom_pattern_schema = {
    type = "object",
    properties = {
        name         = { type = "string", minLength = 1 },
        pattern      = { type = "string", minLength = 1 },
        replace_with = { type = "string" },
        action       = { type = "string", enum = { "mask", "redact", "block", "alert" } },
    },
    required = { "name", "pattern" },
}

local schema = {
    type = "object",
    properties = {
        direction = {
            type = "string",
            enum = { "input", "output", "both" },
            default = "input",
        },
        action = {
            type = "string",
            enum = { "mask", "redact", "block", "alert" },
            default = "mask",
        },
        categories = {
            type = "array",
            items = category_entry_schema,
        },
        custom_patterns = {
            type = "array",
            items = custom_pattern_schema,
            default = {},
        },
        allowlist = {
            type = "array",
            items = { type = "string" },
            default = {},
        },
        unicode = {
            type = "object",
            properties = {
                strip_zero_width = { type = "boolean", default = true },
                strip_bidi       = { type = "boolean", default = true },
                normalize        = { type = "string", enum = { "nfkc", "none" }, default = "nfkc" },
            },
            default = {},
        },
        mask_style = {
            type = "string",
            enum = { "tag", "tag_flat", "partial", "hash" },
            default = "tag",
        },
        restore_on_response = { type = "boolean", default = false },
        preamble = {
            type = "object",
            properties = {
                enable  = { type = "boolean", default = true },
                content = { type = "string" },
            },
            default = {},
        },
        stream_buffer_mode = { type = "boolean", default = false },
        log_detections     = { type = "boolean", default = true },
        log_payload        = { type = "boolean", default = false },
        on_block = {
            type = "object",
            properties = {
                status = { type = "integer", default = 400, minimum = 200, maximum = 599 },
                body   = { type = "string",  default = "Request contains sensitive information that cannot be processed" },
            },
            default = {},
        },
    },
}


local _M = {
    version  = 0.1,
    priority = 1051,
    name     = plugin_name,
    schema   = schema,
}


local DEFAULT_PREAMBLE =
    "Tokens in the form [CATEGORY_N] (e.g. [EMAIL_0], [PHONE_2]) are placeholders " ..
    "for redacted values. Preserve them verbatim in your response: do not modify, " ..
    "rename, quote, or ask the user about them."


-- Normalize categories[] into a {name -> {action, mask_style}} map.
-- * omitted (nil)    -> enable every built-in category.
-- * []               -> enable none (useful when only custom_patterns are wanted).
-- * ["email", ...]   -> enable the named subset.
-- Items may be strings or {name, action?, mask_style?} objects.
local function normalize_categories(conf)
    local out = {}
    if conf.categories == nil then
        for _, name in ipairs(patterns.all_names()) do
            out[name] = { action = conf.action, mask_style = conf.mask_style }
        end
        return out
    end
    for _, item in ipairs(conf.categories) do
        if type(item) == "string" then
            out[item] = { action = conf.action, mask_style = conf.mask_style }
        elseif type(item) == "table" then
            out[item.name] = {
                action     = item.action     or conf.action,
                mask_style = item.mask_style or conf.mask_style,
            }
        end
    end
    return out
end


function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    -- Validate built-in category references.
    if conf.categories then
        for _, item in ipairs(conf.categories) do
            local name = type(item) == "string" and item or item.name
            if not patterns.get(name) then
                return false, "unknown built-in category: " .. tostring(name)
            end
        end
    end

    -- Validate custom patterns are compilable.
    for _, cp in ipairs(conf.custom_patterns or {}) do
        local compiled = re_compile(cp.pattern, "jou")
        if not compiled then
            return false, "invalid custom_patterns regex for " .. cp.name .. ": " .. cp.pattern
        end
    end

    return true
end


-- Build the placeholder string for a given tag + per-request counter.
-- Stable-per-value: identical originals collapse to the same token so
-- coreference is preserved and unmask-on-response can string-match.
local function placeholder_for(vault, tag, original, mask_style)
    if mask_style == "tag_flat" then
        return "[" .. tag .. "]"
    end
    if mask_style == "partial" then
        if #original <= 4 then
            return str_fmt("[%s]", tag)
        end
        return str_sub(original, 1, 2) .. str_fmt("***[%s]", tag)
    end
    if mask_style == "hash" then
        return str_fmt("[%s_%s]", tag, ngx.md5(original):sub(1, 8))
    end

    -- default "tag" style: stable per-value index
    local key = tag .. "\0" .. original
    local existing = vault.by_value[key]
    if existing then
        return existing
    end
    vault.counters[tag] = (vault.counters[tag] or 0) + 1
    local ph = str_fmt("[%s_%d]", tag, vault.counters[tag] - 1)
    vault.by_value[key] = ph
    vault.by_placeholder[ph] = original
    vault.ordered[#vault.ordered + 1] = ph
    return ph
end

-- Plain-literal replace-all. Avoids Lua-pattern escaping entirely by
-- walking the string with string.find(..., plain=true). Short-circuits
-- when the needle is absent so the common zero-hit path allocates
-- nothing. Uses the local str_find upvalue alias that apisix.core.string
-- relies on for the same reason.
local str_find = string.find
local function replace_plain(s, needle, replacement)
    if needle == "" then
        return s
    end
    local first_a = str_find(s, needle, 1, true)
    if not first_a then
        return s
    end
    local parts = {}
    local n = 0
    local idx = 1
    local a, b = first_a, first_a + #needle - 1
    while a do
        n = n + 1; parts[n] = str_sub(s, idx, a - 1)
        n = n + 1; parts[n] = replacement
        idx = b + 1
        a, b = str_find(s, needle, idx, true)
    end
    n = n + 1; parts[n] = str_sub(s, idx)
    return tbl_concat(parts)
end


-- Apply the allowlist by temporarily swapping each literal out for a
-- unique sentinel so the PII regexes never see it. Restored after scan.
local function mask_allowlist(s, allowlist)
    if not allowlist or #allowlist == 0 then
        return s, nil
    end
    local swaps = {}
    for i, literal in ipairs(allowlist) do
        if literal ~= "" and s:find(literal, 1, true) then
            local token = str_fmt("\1ALLOW_%d\1", i)
            s = replace_plain(s, literal, token)
            swaps[token] = literal
        end
    end
    return s, swaps
end


local function unmask_allowlist(s, swaps)
    if not swaps then
        return s
    end
    for token, literal in pairs(swaps) do
        s = replace_plain(s, token, literal)
    end
    return s
end


-- Run one categorized regex over a string, replacing matches with
-- placeholders (or returning early on block/alert).
-- @return new_string, block_reason_or_nil
local function apply_entry(s, entry, cat_cfg, vault, hit_counter, action_override)
    local action = action_override or cat_cfg.action
    local style  = cat_cfg.mask_style
    local tag    = entry.tag
    local validate = entry.validate

    local new, _, err = re_gsub(s, entry.regex, function(m)
        local match = m[0]
        local original = (m[1] and m[1] ~= "") and m[1] or match
        if validate and not validate(original) then
            return match
        end
        hit_counter[entry.name] = (hit_counter[entry.name] or 0) + 1
        if action == "block" then
            vault.block_reason = "category " .. entry.name
            return match
        end
        if action == "redact" then
            return ""
        end
        -- mask / alert: replace the captured span (or full match if no
        -- capture group) with a stable placeholder.
        local ph = placeholder_for(vault, tag, original, style)
        if m[1] and m[1] ~= "" and match ~= m[1] then
            local i, j = match:find(m[1], 1, true)
            if i then
                return match:sub(1, i - 1) .. ph .. match:sub(j + 1)
            end
        end
        return ph
    end, "jou")

    if err then
        core.log.warn("regex failure for category ", entry.name, ": ", err)
        return s, nil
    end
    return new or s, vault.block_reason
end


-- Scan and rewrite a single string. Returns (new_string, block_reason).
local function scan_string(s, cat_map, conf, vault, hit_counter)
    if type(s) ~= "string" or s == "" then
        return s, nil
    end

    s = unicode.harden(s, conf.unicode or {})

    -- Allowlist masking (swap literals out so regex doesn't catch them).
    local s_masked, swaps = mask_allowlist(s, conf.allowlist)
    s = s_masked

    -- Built-in categories, then custom patterns.
    for _, entry in patterns.iter() do
        local cfg = cat_map[entry.name]
        if cfg then
            local new, reason = apply_entry(s, entry, cfg, vault, hit_counter)
            s = new
            if reason then
                return s, reason
            end
        end
    end

    for _, cp in ipairs(conf.custom_patterns or {}) do
        local entry = {
            name    = cp.name,
            tag     = cp.name:upper(),
            regex   = cp.pattern,
        }
        local cfg = { action = cp.action or conf.action, mask_style = conf.mask_style }
        -- For custom patterns with explicit replace_with, use it as a flat tag.
        if cp.replace_with then
            local new, _, err = re_gsub(s, cp.pattern, cp.replace_with, "jou")
            if err then
                core.log.warn("custom regex failure for ", cp.name, ": ", err)
            else
                if new ~= s then
                    hit_counter[cp.name] = (hit_counter[cp.name] or 0) + 1
                end
                s = new or s
            end
        else
            local new, reason = apply_entry(s, entry, cfg, vault, hit_counter)
            s = new
            if reason then
                return s, reason
            end
        end
    end

    -- 4. Restore allowlist.
    s = unmask_allowlist(s, swaps)

    return s, nil
end


-- Walk a body table, scan strings under content/text/input/prompt/instructions
-- keys, mutate in place. Returns block_reason (or nil).
local SCAN_KEYS = {
    content      = true,
    text         = true,
    input        = true,
    prompt       = true,
    instructions = true,
}

local function walk_and_scan(tbl, cat_map, conf, vault, hit_counter)
    if type(tbl) ~= "table" then
        return nil
    end
    for k, v in pairs(tbl) do
        if type(v) == "string" and SCAN_KEYS[k] then
            local new, reason = scan_string(v, cat_map, conf, vault, hit_counter)
            if reason then
                return reason
            end
            tbl[k] = new
        elseif type(v) == "table" then
            local reason = walk_and_scan(v, cat_map, conf, vault, hit_counter)
            if reason then
                return reason
            end
        end
    end
    return nil
end


local function inject_preamble(body_tab, ctx, conf)
    if not conf.restore_on_response then return end
    local pre = conf.preamble or {}
    if pre.enable == false then return end
    local content = pre.content or DEFAULT_PREAMBLE
    protocols.prepend_messages(body_tab, ctx, {
        { role = "system", content = content },
    })
end


local function log_hits(conf, hit_counter, direction, payload)
    if not conf.log_detections then return end
    local parts = {}
    for name, count in pairs(hit_counter) do
        tbl_insert(parts, str_fmt("%s=%d", name, count))
    end
    if #parts == 0 then return end
    if conf.log_payload and payload then
        core.log.info("ai-pii-sanitizer ", direction, " hits: ",
                      tbl_concat(parts, ","), " payload=", payload)
    else
        core.log.info("ai-pii-sanitizer ", direction, " hits: ", tbl_concat(parts, ","))
    end
end


local function deny_response_for_protocol(ctx, conf, reason)
    local body = conf.on_block and conf.on_block.body
              or "Request contains sensitive information that cannot be processed"
    local status = (conf.on_block and conf.on_block.status) or 400

    local proto = protocols.get(ctx.ai_client_protocol)
    if proto and proto.build_deny_response then
        local stream = ctx.var and ctx.var.request_type == "ai_stream"
        local usage  = (proto.empty_usage and proto.empty_usage())
                    or { prompt_tokens = 0, completion_tokens = 0, total_tokens = 0 }
        return status, proto.build_deny_response({
            text   = body,
            model  = ctx.var and ctx.var.request_llm_model,
            usage  = usage,
            stream = stream,
        })
    end

    return status, { message = body, reason = reason }
end


--------------------------------------------------------------------------
-- Request side: access phase
--------------------------------------------------------------------------
function _M.access(conf, ctx)
    if conf.direction == "output" then
        return
    end

    local ct = core.request.header(ctx, "Content-Type")
    if ct and not core.string.has_prefix(ct, "application/json") then
        return
    end

    local raw, err = core.request.get_body()
    if not raw then
        return  -- let ai-proxy handle the missing-body case
    end

    local body_tab, derr = core.json.decode(raw)
    if not body_tab then
        core.log.warn("ai-pii-sanitizer could not decode request body: ", derr)
        return
    end

    local vault = {
        by_value       = {},
        by_placeholder = {},
        counters       = {},
        ordered        = {},
        block_reason   = nil,
    }
    local cat_map = normalize_categories(conf)
    local hits = {}

    local block_reason = walk_and_scan(body_tab, cat_map, conf, vault, hits)

    log_hits(conf, hits, "input", conf.log_payload and raw or nil)

    if block_reason then
        return deny_response_for_protocol(ctx, conf, block_reason)
    end

    inject_preamble(body_tab, ctx, conf)

    -- Only re-encode if something actually changed (saves a JSON round-trip
    -- on the common "no PII" path).
    if next(hits) ~= nil or (conf.restore_on_response and (conf.preamble or {}).enable ~= false) then
        local new_body, eerr = core.json.encode(body_tab)
        if not new_body then
            core.log.error("failed to re-encode sanitized body: ", eerr)
            return
        end
        ngx.req.set_body_data(new_body)
    end

    if conf.restore_on_response then
        ctx.ai_pii_vault = vault
    end
end


--------------------------------------------------------------------------
-- Response side helpers
--------------------------------------------------------------------------
local function restore_from_vault(s, vault)
    if not s or s == "" or not vault then return s end
    for _, ph in ipairs(vault.ordered) do
        local original = vault.by_placeholder[ph]
        if original then
            s = replace_plain(s, ph, original)
        end
    end
    return s
end


-- Sanitize a plain response string (non-stream). Applies restore first
-- (if enabled), then runs the output-direction PII scan.
local function sanitize_response_string(s, conf, ctx)
    if type(s) ~= "string" or s == "" then return s, nil end

    if conf.restore_on_response then
        s = restore_from_vault(s, ctx.ai_pii_vault)
    end

    if conf.direction == "input" then
        return s, nil
    end

    local cat_map = normalize_categories(conf)
    local vault   = { by_value = {}, by_placeholder = {}, counters = {}, ordered = {} }
    local hits    = {}
    local new, reason = scan_string(s, cat_map, conf, vault, hits)
    log_hits(conf, hits, "output", conf.log_payload and s or nil)
    return new, reason
end


-- Rewrite an SSE chunk on the output path: decode, rewrite each
-- delta.content, re-encode. Per-chunk scanning misses PII that straddles
-- chunk boundaries; enable stream_buffer_mode for full-buffer coverage.
local function rewrite_stream_chunk(body, conf, ctx)
    local proto = protocols.get(ctx.ai_client_protocol)
    if not proto then
        return body
    end

    local events = sse.decode(body)
    for _, event in ipairs(events) do
        if proto.is_data_event and proto.is_data_event(event)
                and event.data and event.data ~= "" then
            local parsed, perr = core.json.decode(event.data)
            if parsed then
                -- Mutate delta.content fields in place.
                if type(parsed.choices) == "table" then
                    for _, choice in ipairs(parsed.choices) do
                        if type(choice.delta) == "table"
                                and type(choice.delta.content) == "string" then
                            local new = sanitize_response_string(choice.delta.content, conf, ctx)
                            choice.delta.content = new
                        end
                    end
                end
                event.data = core.json.encode(parsed)
            else
                core.log.warn("ai-pii-sanitizer could not decode SSE event: ", perr)
            end
        end
    end

    local raw = {}
    for _, e in ipairs(events) do
        tbl_insert(raw, sse.encode(e))
    end
    return tbl_concat(raw, "")
end


--------------------------------------------------------------------------
-- Response side: lua_body_filter phase
--------------------------------------------------------------------------
function _M.lua_body_filter(conf, ctx, headers, body)
    -- Skip if nothing to do on the response side.
    if conf.direction == "input" and not conf.restore_on_response then
        return
    end
    if ngx.status >= 400 then
        return
    end

    local request_type = ctx.var and ctx.var.request_type

    if request_type == "ai_chat" then
        -- Non-streaming collected body path. ai-proxy stashes the full text
        -- in ctx.var.llm_response_text and emits the original JSON body
        -- to the client; we need to rewrite the JSON body going out.
        if type(body) ~= "string" or body == "" then
            return
        end
        local parsed, perr = core.json.decode(body)
        if not parsed then
            core.log.warn("ai-pii-sanitizer response body decode failed: ", perr)
            return
        end
        if type(parsed.choices) == "table" then
            for _, choice in ipairs(parsed.choices) do
                if type(choice.message) == "table"
                        and type(choice.message.content) == "string" then
                    choice.message.content = sanitize_response_string(
                        choice.message.content, conf, ctx)
                end
            end
        end
        local new = core.json.encode(parsed)
        if new then
            return ngx.OK, new
        end
        return
    end

    if request_type == "ai_stream" then
        if type(body) ~= "string" or body == "" then
            return
        end
        local rewritten = rewrite_stream_chunk(body, conf, ctx)
        return ngx.OK, rewritten
    end
end


return _M
