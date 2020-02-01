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
local plugin_name = "cors"
local ngx         = ngx
local join        = table.concat
local Origin = 'Origin'
local AccessControlAllowOrigin = 'Access-Control-Allow-Origin'
local AccessControlMaxAge = 'Access-Control-Max-Age'
local AccessControlAllowCredentials = 'Access-Control-Allow-Credentials'
local AccessControlAllowMethods = 'Access-Control-Allow-Methods'
local AccessControlAllowHeaders = 'Access-Control-Allow-headers'
local AccessControlExposeHeaders = 'Access-Control-Expose-Headers'


local schema = {
    type = "object",
    properties = {
        origin = {
            description = "allow cors origin",
            type        = "string"
        },
        headers = {
            description = "allow headers",
            type        = "array"
        },
        expose_headers = {
            description = "allow expose headers",
            type        = "array"
        },
        methods = {
            description = "allow methods for cors",
            type = "array",
            items = {
                description = "HTTP method",
                type = "string",
                enum = {"GET", "POST", "PUT", "DELETE", "PATCH", "HEAD",
                        "OPTIONS", "CONNECT", "TRACE"}
            }
        },
        max_age = {
            description = "max age",
            type        = "integer",
            default     = 3600
        },
        credentials = {
            description = "is or not allow cookie or auth info",
            type        = "boolean",
            default     = true
        }
    }
}

local _M = {
    version = 0.1,
    priority = 1,
    -- type = 'cors',
    name = plugin_name,
    schema = schema,
}

function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end
    return true
end

function _M.header_filter(conf, ctx)
    local allow_hosts
    local allow_headers
    local allow_methods
    local allow_expose_headers
    local allow_credentials = true
    local max_age = 3600
    local headers = ngx.req.get_headers()
    local allow_origin = headers[Origin]
    if not allow_origin then
        return
    end
    --if you set origin. support pattern eg. *.example.com
    if conf["origin"] then
        local domain, _, err = ngx.re.find(allow_origin, conf["origin"], "jo")
        if not domain then
            core.log.err("could not match origin: ", err)
            return
        end
    end
    ngx.header[AccessControlAllowOrigin] = allow_origin
    ngx.header[AccessControlMaxAge] = max_age
    -- if set methods .  the default is actual request method
    if conf["methods"] then
        allow_methods = join(conf["methods"], ',')
        ngx.header[AccessControlAllowMethods] = allow_methods
    end
    -- if set headers .  the default is actual request headers
    if conf["headers"] then
        allow_headers = join(conf["headers"], ',')
        ngx.header[AccessControlAllowHeaders] = allow_headers
    end
    -- if set expose headers .  the default is actual request headers
    if conf["expose_headers"] then
        allow_headers = join(conf["expose_headers"], ',')
        ngx.header[AccessControlExposeHeaders] = allow_expose_headers
    end
    -- if set credentials  allow cookie or auth information.  the default is true
    if conf['credentials'] then
        allow_credentials = conf['credentials']
    end
    
    ngx.header[AccessControlAllowCredentials] = conf['credentials']
end
return _M