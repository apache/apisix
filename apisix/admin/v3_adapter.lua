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

local fetch_local_conf  = require("apisix.core.config_local").local_conf
local try_read_attr     = require("apisix.core.table").try_read_attr
local log               = require("apisix.core.log")
local request           = require("apisix.core.request")
local response          = require("apisix.core.response")
local table             = require("apisix.core.table")
local tonumber          = tonumber

local _M = {}


local admin_api_version
local function enable_v3()
    if admin_api_version then
        if admin_api_version == "v3" then
            return true
        end

        if admin_api_version == "default" then
            return false
        end
    end

    local local_conf, err = fetch_local_conf()
    if not local_conf then
        admin_api_version = "default"
        log.error("failed to fetch local conf: ", err)
        return false
    end

    local api_ver = try_read_attr(local_conf, "apisix", "admin_api_version")
    if api_ver ~= "v3" then
        admin_api_version = "default"
        return false
    end

    admin_api_version = api_ver
    return true
end
_M.enable_v3 = enable_v3


function _M.to_v3(body, action)
    if not enable_v3() then
        body.action = action
    end
end


function _M.to_v3_list(body)
    if not enable_v3() then
        return
    end

    if body.node.dir then
        body.list = body.node.nodes
        body.node = nil
    end
end


local function sort(l, r)
    return l.createdIndex < r.createdIndex
end


function _M.filter(body)
    if not enable_v3() then
        return
    end

    local args = request.get_uri_args()
    args.page = tonumber(args.page)
    args.page_size = tonumber(args.page_size)
    if not args.page or not args.page_size then
        return
    end

    if args.page_size < 10 or args.page_size > 500 then
        return response.exit(400, "page_size must be between 10 and 500")
    end

    if not args.page or args.page < 1 then
        -- default page is 1
        args.page = 1
    end

    local list = body.list

    -- sort nodes by there createdIndex
    table.sort(list, sort)

    local to = args.page * args.page_size
    local from =  to - args.page_size + 1

    local res = table.new(20, 0)

    for i = from, to do
        if list[i] then
            res[i - from + 1] = list[i]
        end
    end

    body.list = res
end


return _M
