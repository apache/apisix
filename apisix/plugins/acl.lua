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
local type      = type
local ipairs    = ipairs
local pairs     = pairs
local jp        = require("jsonpath")
local re_split  = require("ngx.re").split
local core      = require("apisix.core")
local schema = {
    type = "object",
    properties = {
        external_user_label_field = {type = "string", default = "groups", minLength = 1},
        external_user_label_field_key = {type = "string", minLength = 1},
        external_user_label_field_parser = {
            type = "string",
            enum = {"segmented_text", "json", "table"},
        },
        external_user_label_field_separator = {
            type = "string",
            minLength = 1,
            description = "The separator(regex) of the segmented_text parser",
        },
        allow_labels = {
            type = "object",
            minProperties = 1,
            patternProperties = {
                [".*"] = {
                    type = "array",
                    minItems = 1,
                    items = {type = "string"}
                },
            },
        },
        deny_labels = {
            type = "object",
            minProperties = 1,
            patternProperties = {
                [".*"] = {
                    type = "array",
                    minItems = 1,
                    items = {type = "string"}
                },
            },
        },
        rejected_code = {type = "integer", minimum = 200, default = 403},
        rejected_msg = {type = "string"},
    },
    allOf = {
        {
            ["if"] = {
                required = { "external_user_label_field_parser" },
                properties = { external_user_label_field_parser = { const = "segmented_text" } },
            },
            ["then"] = {
                required = { "external_user_label_field_separator" },
            },
        },
    },
    anyOf = {
        {required = {"allow_labels"}},
        {required = {"deny_labels"}}
    },
}

local plugin_name = "acl"

local _M = {
    version = 0.1,
    priority = 2410,
    name = plugin_name,
    schema = schema,
}

local parsers = {
    SEGMENTED_TEXT = "segmented_text",
    JSON = "json",
    TABLE = "table",
}


local function extra_values_with_parser(value, parser, sep)
    local values = {}
    if parser == parsers.SEGMENTED_TEXT then
        sep = "\\s*" .. sep .. "\\s*"
        local res, err = re_split(value, sep, "jo")
        if res then
            return res
        end
        core.log.warn("failed to split labels [", value, "], err: ", err)

        return values
    end

    local typ = type(value)

    if parser == parsers.TABLE then
        if typ == "table" then
            return value
        end
        core.log.warn("the parser is specified as table, but the type of value is not table: ", typ)
        return values
    end

    if parser == parsers.JSON then
        if typ ~= "string" then
            core.log.warn("the parser is specified as json array, but the value type is not string")
            return values
        end
        if not core.string.has_prefix(value, "[") then
            core.log.warn("the parser is specified as json array, ",
                          "but the value do not has prefix '['")
            return values
        end

        local res, err = core.json.decode(value)
        if res then
            return res
        end
        core.log.warn("failed to decode labels [", value, "] as array, err: ", err)
        return values
    end

    return values
end


local function extra_values_without_parser(value)
    local values = {}
    local typ = type(value)

    if typ == "table" then
        return extra_values_with_parser(value, parsers.TABLE, "")
    end

    if typ == "string" then
        if core.string.has_prefix(value, "[") then
            return extra_values_with_parser(value, parsers.JSON, "")
        end
        if core.string.find(value, ",") then
            return extra_values_with_parser(value, parsers.SEGMENTED_TEXT, ",")
        end
        core.log.info("the string value can not parsed by ", parsers.JSON,
                      " or ",parsers.SEGMENTED_TEXT)
        return { value }
    end

    core.log.error("unsupported type of label value: ", typ)
    return values
end


local function contains_value(want_values, value, parser, sep)
    local values
    if parser then
        values = extra_values_with_parser(value, parser, sep)
    else
        values = extra_values_without_parser(value)
    end

    for _, want in ipairs(want_values) do
        for _, value in ipairs(values) do
            if want == value then
                return true
            end
        end
    end
    return false
end


local function contains_label(want_labels, labels, parser, sep)
    if not labels then
        return false
    end
    for key, values in pairs(want_labels) do
        if labels[key] and contains_value(values, labels[key], parser, sep) then
            return true
        end
    end
    return false
end

local function reject(conf)
    if conf.rejected_msg then
        return conf.rejected_code , { message = conf.rejected_msg }
    end
    return conf.rejected_code , { message = "The consumer is forbidden."}
end

function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    local _, parse_err = jp.parse(conf.external_user_label_field)
    if parse_err then
        return false, "invalid external_user_label_field: " .. parse_err
    end

    return true
end

function _M.access(conf, ctx)
    local labels
    local parser, sep
    if ctx.consumer then
        labels = ctx.consumer.labels
    elseif ctx.external_user then
        local label_key = conf.external_user_label_field
        if conf.external_user_label_field_key then
            label_key = conf.external_user_label_field_key
        end
        local label_value = jp.value(ctx.external_user, conf.external_user_label_field)
        labels = { [label_key] = label_value }
        parser = conf.external_user_label_field_parser
        sep = conf.external_user_label_field_separator
    else
        return 401, { message = "Missing authentication."}
    end

    core.log.debug("consumer's or user's labels: ", core.json.delay_encode(labels))

    if conf.deny_labels then
        if contains_label(conf.deny_labels, labels, parser, sep) then
            return reject(conf)
        end
    end

    if conf.allow_labels then
        if not contains_label(conf.allow_labels, labels, parser, sep) then
            return reject(conf)
        end
    end
end

return _M
