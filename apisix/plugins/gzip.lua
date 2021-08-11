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
local core = require("apisix.core")
local is_apisix_or, response = pcall(require, "resty.apisix.response")
local ngx_header = ngx.header
local req_http_version = ngx.req.http_version
local str_sub = string.sub
local ipairs = ipairs
local tonumber = tonumber


local schema = {
    type = "object",
    properties = {
        types = {
            type = "array",
            minItems = 1,
            items = {
                type = "string",
                minLength = 1,
            },
            default = {"text/html"}
        },
        min_length = {
            type = "integer",
            minimum = 1,
            default = 20,
        },
        comp_level = {
            type = "integer",
            minimum = 1,
            maximum = 9,
            default = 1,
        },
        http_version = {
            enum = {1.1, 1.0},
            default = 1.1,
        },
        buffers = {
            type = "object",
            properties = {
                number = {
                    type = "integer",
                    minimum = 1,
                    default = 32,
                },
                size = {
                    type = "integer",
                    minimum = 1,
                    default = 4096,
                }
            },
            default = {
                number = 32,
                size = 4096,
            }
        },
        vary = {
            type = "boolean",
        }
    },
}


local plugin_name = "gzip"


local _M = {
    version = 0.1,
    priority = 995,
    name = plugin_name,
    schema = schema,
}


function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end


function _M.header_filter(conf, ctx)
    if not is_apisix_or then
        core.log.error("need to build APISIX-OpenResty to support setting gzip")
        return 501
    end

    local types = conf.types
    local content_type = ngx_header["Content-Type"]
    if not content_type then
        -- Like Nginx, don't gzip if Content-Type is missing
        return
    end
    local from = core.string.find(content_type, ";")
    if from then
        content_type = str_sub(content_type, 1, from - 1)
    end

    local matched = false
    for _, ty in ipairs(types) do
        if content_type == ty then
            matched = true
            break
        end
    end
    if not matched then
        return
    end

    local content_length = tonumber(ngx_header["Content-Length"])
    if content_length then
        local min_length = conf.min_length
        if content_length < min_length then
            return
        end
        -- Like Nginx, don't check min_length if Content-Length is missing
    end

    local http_version = req_http_version()
    if http_version < conf.http_version then
        return
    end

    local buffers = conf.buffers

    core.log.info("set gzip with buffers: ", buffers.number, " ", buffers.size,
                  ", level: ", conf.comp_level)

    local ok, err = response.set_gzip({
        buffer_num = buffers.number,
        buffer_size = buffers.size,
        compress_level = conf.comp_level,
    })
    if not ok then
        core.log.error("failed to set gzip: ", err)
        return
    end

    if conf.vary then
        core.response.add_header("Vary", "Accept-Encoding")
    end
end


return _M
