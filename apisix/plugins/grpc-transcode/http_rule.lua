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
-- Build a routing table from google.api.http on the compiled proto.
-- lua-protobuf resolves the extension as `method.options.http` when the
-- descriptor set was built with --include_imports.
--
local core            = require("apisix.core")
local proto_fake_file = require("apisix.plugins.grpc-transcode.proto").proto_fake_file
local ipairs          = ipairs
local pairs           = pairs
local type            = type
local table           = table
local string          = string
local re_match        = ngx.re.match


local _M = {version = 0.1}


-- `custom` is left out: its free-form `kind` has no fixed HTTP verb to match on.
local supported_patterns = {
    get    = "GET",
    put    = "PUT",
    post   = "POST",
    delete = "DELETE",
    patch  = "PATCH",
}


local function escape_literal(s)
    return (string.gsub(s, "[%^%$%(%)%.%[%]%*%+%-%?%{%}|\\]", "\\%0"))
end


-- Split on "/", but treat a `{...}` variable as opaque: its own sub-template
-- may contain slashes, as in `{name=shelves/*/books/*}`.
local function split_segments(path)
    local segments = {}
    local buf = {}
    local depth = 0

    for i = 1, #path do
        local c = string.sub(path, i, i)
        if c == "{" then
            depth = depth + 1
            buf[#buf + 1] = c
        elseif c == "}" then
            depth = depth - 1
            buf[#buf + 1] = c
        elseif c == "/" and depth == 0 then
            segments[#segments + 1] = table.concat(buf)
            core.table.clear(buf)
        else
            buf[#buf + 1] = c
        end
    end
    segments[#segments + 1] = table.concat(buf)

    return segments
end


-- `FieldPath = IDENT { "." IDENT }`; nil for anything else, which also catches
-- an empty name, a stray "=", and leading, trailing or doubled dots.
local function parse_field_path(field_path)
    local path = {}
    for part in string.gmatch(field_path, "[^.]+") do
        if not string.match(part, "^[%a_][%w_]*$") then
            return nil
        end
        path[#path + 1] = part
    end

    if #path == 0 or table.concat(path, ".") ~= field_path then
        return nil
    end

    return path
end


-- Convert the segments inside a variable into a regex fragment.
local function segments_to_regex(segments)
    local out = {}

    for i, seg in ipairs(segments) do
        local sep = i > 1 and "/" or ""

        if seg == "*" then
            out[#out + 1] = sep .. "[^/]+"
        elseif seg == "**" then
            -- Zero or more segments, so the separator in front goes with it.
            out[#out + 1] = i > 1 and "(?:/.*)?" or ".*"
        elseif string.sub(seg, 1, 1) == "{" then
            return nil, "nested variable in path template"
        else
            out[#out + 1] = sep .. escape_literal(seg)
        end
    end

    return table.concat(out)
end


-- Parse a path template to a PCRE plus ordered field paths. Captures are
-- positional because `{user.id}` is not a legal PCRE group name.
function _M.parse_path_template(tmpl)
    if type(tmpl) ~= "string" or string.sub(tmpl, 1, 1) ~= "/" then
        return nil, "path template must start with '/'"
    end

    -- A trailing ":verb" is part of the last segment, not a path separator.
    local path, verb = string.match(tmpl, "^(.-):([^/:{}]+)$")
    if not path then
        path = tmpl
    end

    local segments = split_segments(path)
    -- `path` starts with "/", so the first segment is always empty.
    table.remove(segments, 1)

    local buf = {"^"}
    local vars = {}
    local literal_count = 0
    -- `**` spans segments, so the spec only allows it in the final one.
    local multi_at

    for i, seg in ipairs(segments) do
        -- `**` is zero or more segments, so `/v1/{name=**}` matches a bare `/v1`.
        local last = i == #segments

        if string.sub(seg, 1, 1) == "{" then
            if string.sub(seg, -1) ~= "}" then
                return nil, "unbalanced '{' in path template"
            end

            local inner = string.sub(seg, 2, -2)
            local field_path, sub_tmpl = string.match(inner, "^([^=]+)=(.+)$")
            if not field_path then
                -- `{id}` is shorthand for `{id=*}`
                field_path, sub_tmpl = inner, "*"
            end

            local parsed_field = parse_field_path(field_path)
            if not parsed_field then
                return nil, "invalid field path in path template"
            end

            local sub_segments = split_segments(sub_tmpl)
            local frag, err = segments_to_regex(sub_segments)
            if not frag then
                return nil, err
            end

            if sub_segments[#sub_segments] == "**" then
                multi_at = i
            end

            if last and sub_tmpl == "**" then
                buf[#buf + 1] = "(?:/(" .. frag .. "))?"
            else
                buf[#buf + 1] = "/(" .. frag .. ")"
            end
            vars[#vars + 1] = parsed_field
        elseif seg == "*" then
            buf[#buf + 1] = "/[^/]+"
        elseif seg == "**" then
            multi_at = i
            if last then
                buf[#buf + 1] = "(?:/.*)?"
            else
                buf[#buf + 1] = "/.*"
            end
        else
            buf[#buf + 1] = "/" .. escape_literal(seg)
            literal_count = literal_count + 1
        end
    end

    if multi_at and multi_at < #segments then
        return nil, "'**' must be the last segment in a path template"
    end

    buf[#buf + 1] = "$"

    -- Verb is compared outside the regex.
    return table.concat(buf), vars, literal_count, verb
end


-- `Template = "/" Segments [ Verb ]`; a colon outside the final segment is
-- an ordinary character.
local function split_verb(uri)
    local path, verb = string.match(uri, "^(.*):([^/:]+)$")
    if path then
        return path, verb
    end

    return uri, nil
end


-- Prefer more literals, then fewer vars, then name.
local function cmp_rule(a, b)
    if a.literal_count ~= b.literal_count then
        return a.literal_count > b.literal_count
    end

    if #a.vars ~= #b.vars then
        return #a.vars < #b.vars
    end

    if a.service ~= b.service then
        return a.service < b.service
    end

    if a.method ~= b.method then
        return a.method < b.method
    end

    return a.regex < b.regex
end


local function add_rule(rules, service, method, http)
    local pattern = http.pattern
    local http_method = pattern and supported_patterns[pattern]
    if not http_method then
        return
    end

    local tmpl = http[pattern]
    if type(tmpl) ~= "string" or tmpl == "" then
        return
    end

    local regex, vars, literal_count, verb = _M.parse_path_template(tmpl)
    if not regex then
        -- `vars` carries the error message on failure.
        core.log.warn("ignoring google.api.http rule for ", service, "/", method,
                      ": ", vars)
        return
    end

    local bucket = rules[http_method]
    if not bucket then
        bucket = {}
        rules[http_method] = bucket
    end

    bucket[#bucket + 1] = {
        service       = service,
        method        = method,
        regex         = regex,
        vars          = vars,
        literal_count = literal_count,
        verb          = verb,
        body          = http.body,
    }
end


function _M.build(proto_obj)
    local loaded = proto_obj[proto_fake_file]
    if type(loaded) ~= "table" or type(loaded.index) ~= "table" then
        return nil, "compiled proto not found"
    end

    local rules = {}
    local count = 0

    for service, methods in pairs(loaded.index) do
        for method, descriptor in pairs(methods) do
            local http = descriptor.options and descriptor.options.http
            if type(http) == "table" then
                add_rule(rules, service, method, http)

                for _, binding in ipairs(http.additional_bindings or {}) do
                    add_rule(rules, service, method, binding)
                end
            end
        end
    end

    for _, bucket in pairs(rules) do
        table.sort(bucket, cmp_rule)
        count = count + #bucket
    end

    if count == 0 then
        return nil, "no google.api.http annotation found in the proto, make sure it "
                    .. "was compiled with `protoc --include_imports --descriptor_set_out`"
    end

    return rules
end


-- Cache the table on the proto object: `proto.fetch` holds it in an lrucache
-- keyed by config version, so it is dropped when the proto changes.
function _M.fetch(proto_obj)
    if proto_obj.http_rules then
        return proto_obj.http_rules
    end

    if proto_obj.http_rules_err then
        return nil, proto_obj.http_rules_err
    end

    local rules, err = _M.build(proto_obj)
    if not rules then
        proto_obj.http_rules_err = err
        return nil, err
    end

    proto_obj.http_rules = rules
    return rules
end


local function set_nested(tbl, field_path, value)
    local node = tbl
    for i = 1, #field_path - 1 do
        local key = field_path[i]
        if type(node[key]) ~= "table" then
            node[key] = {}
        end
        node = node[key]
    end

    node[field_path[#field_path]] = value
end


-- Methods bound to this uri, sorted. Tells 405 apart from 404.
function _M.allowed_methods(rules, uri)
    local allowed
    local path, verb = split_verb(uri)

    for http_method, bucket in pairs(rules) do
        for _, rule in ipairs(bucket) do
            if rule.verb == verb and re_match(path, rule.regex, "jo") then
                allowed = allowed or {}
                allowed[#allowed + 1] = http_method
                break
            end
        end
    end

    if allowed then
        table.sort(allowed)
    end

    return allowed
end


-- Returns the matched rule and the captured values, keyed by field path.
-- `uri` is already percent-decoded, so captures are used as-is and %2F has
-- become a real '/'.
function _M.match(rules, http_method, uri)
    local bucket = rules[http_method]
    if not bucket then
        return nil
    end

    local path, verb = split_verb(uri)

    for _, rule in ipairs(bucket) do
        -- Verb must match, absent included.
        local captures, err
        if rule.verb == verb then
            captures, err = re_match(path, rule.regex, "jo")
        end

        if err then
            core.log.error("failed to match uri ", uri, " against ", rule.regex, ": ", err)
        elseif captures then
            local params
            if #rule.vars > 0 then
                params = {}
                for i, field_path in ipairs(rule.vars) do
                    -- Missing `**` capture means an empty value.
                    set_nested(params, field_path, captures[i] or "")
                end
            end

            return rule, params
        end
    end

    return nil
end


return _M
