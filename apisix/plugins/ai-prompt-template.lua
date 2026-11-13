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
local core          = require("apisix.core")
local body          = require("apisix.plugins.ai-prompt.body")
local prompt_schema = require("apisix.plugins.ai-prompt.schema")
local template      = require("resty.template")
local ipairs        = ipairs
local pcall         = pcall
local string_gsub   = string.gsub

local schema = {
    type = "object",
    properties = {
        max_req_body_size = {
            type = "integer",
            minimum = 1,
            default = 67108864,
            description = "maximum request body size in bytes buffered into "
                       .. "memory; larger request bodies are rejected",
        },
        templates = {
            type = "array",
            minItems = 1,
            items = {
                type = "object",
                properties = {
                    name = {
                        type = "string",
                        minLength = 1,
                    },
                    template = {
                        type = "object",
                        properties = {
                            model = {
                                type = "string",
                                minLength = 1,
                            },
                            messages = prompt_schema.messages,
                        }
                    }
                },
                required = {"name", "template"}
            }
        },
    },
    required = {"templates"},
}


local _M = {
    version  = 0.1,
    priority = 1071,
    name     = "ai-prompt-template",
    schema   = schema,
}

local templates_lrucache = core.lrucache.new({
    ttl = 300, count = 256
})

function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end


local function find_template(conf, template_name)
    for _, template in ipairs(conf.templates) do
        if template.name == template_name then
            return template.template
        end
    end
    return nil
end


local function render_string(value, input)
    local raw_template = string_gsub(value, "{{(.-)}}", "{*%1*}")
    local ok, render = pcall(template.compile, raw_template)
    if not ok then
        return nil, "template compile: " .. render
    end

    local output
    ok, output = pcall(render, input)
    if not ok then
        return nil, "template rendering: " .. output
    end
    return output
end


local function render_template(configured, input)
    local rendered = core.table.deepcopy(configured)
    local err

    if rendered.model then
        rendered.model, err = render_string(rendered.model, input)
        if not rendered.model then
            return nil, err
        end
    end

    for _, message in ipairs(rendered.messages or {}) do
        message.content, err = render_string(message.content, input)
        if not message.content then
            return nil, err
        end
    end

    return rendered
end


function _M.rewrite(conf, ctx)
    local body_tab, status, err = body.read(conf.max_req_body_size)
    if not body_tab then
        return status, err
    end
    local template_name = body_tab.template_name
    if not template_name then
        return 400, { message = "template name is missing in request." }
    end

    local template = templates_lrucache(template_name, conf, find_template, conf, template_name)
    if not template then
        return 400, { message = "template: " .. template_name .. " not configured." }
    end

    local rendered, render_err = render_template(template, body_tab)
    if not rendered then
        return 503, {message = render_err}
    end

    body.replace(body_tab, rendered)
    return body.write(ctx, body_tab)
end


return _M
