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
local core    = require("apisix.core")
local ngx_time = ngx.time
local tonumber = tonumber


local _M = {}


local function inject_timestamp(conf, prev_conf, patch_conf)
    if not conf.create_time then
        if prev_conf and prev_conf.node.value.create_time then
            conf.create_time = prev_conf.node.value.create_time
        else
            -- As we don't know existent data's create_time, we have to pretend
            -- they are created now.
            conf.create_time = ngx_time()
        end
    end

    if not conf.update_time or
        -- For PATCH request, the modification is passed as 'patch_conf'
        -- If the sub path is used, the 'patch_conf' will be a placeholder `true`
        (patch_conf and (patch_conf == true or patch_conf.update_time == nil))
    then
        -- reset the update_time if:
        -- 1. PATCH request, with sub path
        -- 2. PATCH request, update_time not given
        -- 3. Other request, update_time not given
        conf.update_time = ngx_time()
    end
end
_M.inject_timestamp = inject_timestamp


function _M.inject_conf_with_prev_conf(kind, key, conf)
    local res, err = core.etcd.get(key)
    if not res or (res.status ~= 200 and res.status ~= 404) then
        core.log.error("failed to get " .. kind .. "[", key, "] from etcd: ", err or res.status)
        return nil, err
    end

    if res.status == 404 then
        inject_timestamp(conf)
    else
        inject_timestamp(conf, res.body)
    end

    return true
end


local function sort(l, r)
    return l.createdIndex < r.createdIndex
end

function _M.pagination(body)
    local args = core.request.get_uri_args()
    if not args.page or not args.page_size then
        return
    end

    args.page = tonumber(args.page)
    args.page_size = tonumber(args.page_size)

    if args.page_size < 10 or args.page_size > 500 then
        return core.response.exit(400, "page_size must be between 10 and 500")
    end

    if not args.page or args.page < 1 then
        -- default page is 1
        args.page = 1
    end

    local list = (body.node and body.node.nodes) or body.list

    -- sort nodes by there createdIndex
    core.table.sort(list, sort)

    local to = args.page * args.page_size
    local form =  to - args.page_size + 1
    local res = core.table.new(args.page_size, 0)

    for i = form, to do
        if list[i] then
            res[i - form + 1] = list[i]
        end
    end

    body.list = res
end


-- fix_count makes the "count" field returned by etcd reasonable
function _M.fix_count(body, id)
    if body.count then
        if not id then
            -- remove the count of placeholder (init_dir)
            body.count = tonumber(body.count) - 1
        else
            body.count = tonumber(body.count)
        end
    end
end


return _M
