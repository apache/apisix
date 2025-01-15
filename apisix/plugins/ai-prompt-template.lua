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
local core              = require("apisix.core")
local body_transformer  = require("apisix.plugins.body-transformer")
local ipairs            = ipairs

local prompt_schema = {
    properties = {
        role = {
            type = "string",
            enum = { "system", "user", "assistant" }
        },
        content = {
            type = "string",
            minLength = 1,
        }
    },
    required = { "role", "content" }
}

local prompts = {
    type = "array",
    minItems = 1,
    items = prompt_schema
}

local schema = {
    type = "object",
    properties = {
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
                            messages = prompts
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

local templates_json_lrucache = core.lrucache.new({
    ttl = 300, count = 256
})

function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end


local function get_request_body_table()
    local body, err = core.request.get_body()
    if not body then
        return nil, { message = "could not get body: " .. err }
    end

    local body_tab, err = core.json.decode(body)
    if not body_tab then
        return nil, { message = "could not get parse JSON request body: ", err }
    end

    return body_tab
end


local function find_template(conf, template_name)
    for _, template in ipairs(conf.templates) do
        if template.name == template_name then
            return template.template
        end
    end
    return nil
end

function _M.rewrite(conf, ctx)
    local body_tab, err = get_request_body_table()
    if not body_tab then
        return 400, err
    end
    local template_name = body_tab.template_name
    if not template_name then
        return 400, { message = "template name is missing in request." }
    end

    local template = templates_lrucache(template_name, conf, find_template, conf, template_name)
    if not template then
        return 400, { message = "template: " .. template_name .. " not configured." }
    end

    local template_json = templates_json_lrucache(template, template, core.json.encode, template)
    core.log.info("sending template to body_transformer: ", template_json)
    return body_transformer.rewrite(
        {
            request = {
                template = template_json,
                input_format = "json"
            }
        },
        ctx
    )
end


return _M
