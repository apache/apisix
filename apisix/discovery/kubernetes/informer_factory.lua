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

local ngx = ngx
local ipairs = ipairs
local string = string
local math = math
local type = type
local core = require("apisix.core")
local http = require("resty.http")

local function list_query(informer)
    local arguments = {
        limit = informer.limit,
    }

    if informer.continue and informer.continue ~= "" then
        arguments.continue = informer.continue
    end

    if informer.label_selector and informer.label_selector ~= "" then
        arguments.labelSelector = informer.label_selector
    end

    if informer.field_selector and informer.field_selector ~= "" then
        arguments.fieldSelector = informer.field_selector
    end

    return ngx.encode_args(arguments)
end


local function list(httpc, apiserver, informer)
    local response, err = httpc:request({
        path = informer.path,
        query = list_query(informer),
        headers = {
            ["Host"] = apiserver.host .. ":" .. apiserver.port,
            ["Authorization"] = "Bearer " .. apiserver.token,
            ["Accept"] = "application/json",
            ["Connection"] = "keep-alive"
        }
    })

    core.log.info("--raw=", informer.path, "?", list_query(informer))

    if not response then
        return false, "RequestError", err or ""
    end

    if response.status ~= 200 then
        return false, response.reason, response:read_body() or ""
    end

    local body, err = response:read_body()
    if err then
        return false, "ReadBodyError", err
    end

    local data = core.json.decode(body)
    if not data or data.kind ~= informer.list_kind then
        return false, "UnexpectedBody", body
    end

    informer.version = data.metadata.resourceVersion

    if informer.on_added then
        for _, item in ipairs(data.items or {}) do
            informer:on_added(item, "list")
        end
    end

    informer.continue = data.metadata.continue
    if informer.continue and informer.continue ~= "" then
        list(httpc, apiserver, informer)
    end

    return true
end


local function watch_query(informer)
    local arguments = {
        watch = "true",
        allowWatchBookmarks = "true",
        timeoutSeconds = informer.overtime,
    }

    if informer.version and informer.version ~= "" then
        arguments.resourceVersion = informer.version
    end

    if informer.label_selector and informer.label_selector ~= "" then
        arguments.labelSelector = informer.label_selector
    end

    if informer.field_selector and informer.field_selector ~= "" then
        arguments.fieldSelector = informer.field_selector
    end

    return ngx.encode_args(arguments)
end


local function split_event (body, callback, ...)
    local gmatch_iterator, err = ngx.re.gmatch(body, "{\"type\":.*}\n", "jao")
    if not gmatch_iterator then
        return false, nil, "GmatchError", err
    end

    local captures
    local captured_size = 0
    local ok, reason
    while true do
        captures, err = gmatch_iterator()

        if err then
            return false, nil, "GmatchError", err
        end

        if not captures then
            break
        end

        captured_size = captured_size + #captures[0]

        ok, reason, err = callback(captures[0], ...)
        if not ok then
            return false, nil, reason, err
        end
    end

    local remainder_body
    if captured_size == #body then
        remainder_body = ""
    elseif captured_size == 0 then
        remainder_body = body
    elseif captured_size < #body then
        remainder_body = string.sub(body, captured_size + 1)
    end

    return true, remainder_body
end


local function dispatch_event(event_string, informer)
    local event = core.json.decode(event_string)

    if not event or not event.type or not event.object then
        return false, "UnexpectedBody", event_string
    end

    local tp = event.type

    if tp == "ERROR" then
        if event.object.code == 410 then
            return false, "ResourceGone", nil
        end
        return false, "UnexpectedBody", event_string
    end

    local object = event.object
    informer.version = object.metadata.resourceVersion

    if tp == "ADDED" then
        if informer.on_added then
            informer:on_added(object, "watch")
        end
    elseif tp == "DELETED" then
        if informer.on_deleted then
            informer:on_deleted(object)
        end
    elseif tp == "MODIFIED" then
        if informer.on_modified then
            informer:on_modified(object)
        end
        -- elseif type == "BOOKMARK" then
        --    do nothing
    end

    return true
end


local function watch(httpc, apiserver, informer)
    local watch_times = 8
    for _ = 1, watch_times do
        local watch_seconds = 1800 + math.random(9, 999)
        informer.overtime = watch_seconds
        local http_seconds = watch_seconds + 120
        httpc:set_timeouts(2000, 3000, http_seconds * 1000)

        local response, err = httpc:request({
            path = informer.path,
            query = watch_query(informer),
            headers = {
                ["Host"] = apiserver.host .. ":" .. apiserver.port,
                ["Authorization"] = "Bearer " .. apiserver.token,
                ["Accept"] = "application/json",
                ["Connection"] = "keep-alive"
            }
        })

        core.log.info("--raw=", informer.path, "?", watch_query(informer))

        if err then
            return false, "RequestError", err
        end

        if response.status ~= 200 then
            return false, response.reason, response:read_body() or ""
        end

        local ok
        local remainder_body
        local body
        local reason

        while true do
            body, err = response.body_reader()
            if err then
                return false, "ReadBodyError", err
            end

            if not body then
                break
            end

            if remainder_body and #remainder_body > 0 then
                body = remainder_body .. body
            end

            ok, remainder_body, reason, err = split_event(body, dispatch_event, informer)
            if not ok then
                if reason == "ResourceGone" then
                    return true
                end
                return false, reason, err
            end
        end
    end

    return true
end


local function list_watch(informer, apiserver)
    local ok
    local reason, message
    local httpc = http.new()

    informer.continue = ""
    informer.version = ""

    informer.fetch_state = "connecting"
    core.log.info("begin to connect ", apiserver.host, ":", apiserver.port)

    ok, message = httpc:connect({
        scheme = apiserver.schema,
        host = apiserver.host,
        port = apiserver.port,
        ssl_verify = false
    })

    if not ok then
        informer.fetch_state = "connect failed"
        core.log.error("connect apiserver failed, apiserver.host: ", apiserver.host,
                ", apiserver.port: ", apiserver.port, ", message : ", message)
        return false
    end

    core.log.info("begin to list ", informer.kind)
    informer.fetch_state = "listing"
    if informer.pre_List then
        informer:pre_list()
    end

    ok, reason, message = list(httpc, apiserver, informer)
    if not ok then
        informer.fetch_state = "list failed"
        core.log.error("list failed, kind: ", informer.kind,
                ", reason: ", reason, ", message : ", message)
        return false
    end

    informer.fetch_state = "list finished"
    if informer.post_List then
        informer:post_list()
    end

    core.log.info("begin to watch ", informer.kind)
    informer.fetch_state = "watching"
    ok, reason, message = watch(httpc, apiserver, informer)
    if not ok then
        informer.fetch_state = "watch failed"
        core.log.error("watch failed, kind: ", informer.kind,
                ", reason: ", reason, ", message : ", message)
        return false
    end

    informer.fetch_state = "watch finished"

    return true
end

local _M = {
}

function _M.new(group, version, kind, plural, namespace)
    local tp
    tp = type(group)
    if tp ~= "nil" and tp ~= "string" then
        return nil, "group should set to string or nil type but " .. tp
    end

    tp = type(namespace)
    if tp ~= "nil" and tp ~= "string" then
        return nil, "namespace should set to string or nil type but " .. tp
    end

    tp = type(version)
    if tp ~= "string" or version == "" then
        return nil, "version should set to non-empty string"
    end

    tp = type(kind)
    if tp ~= "string" or kind == "" then
        return nil, "kind should set to non-empty string"
    end

    tp = type(plural)
    if tp ~= "string" or plural == "" then
        return nil, "plural should set to non-empty string"
    end

    local path = ""
    if group == nil or group == "" then
        path = path .. "/api/" .. version
    else
        path = path .. "/apis/" .. group .. "/" .. version
    end

    if namespace and namespace ~= "" then
        path = path .. "/namespace/" .. namespace
    end
    path = path .. "/" .. plural

    return {
        kind = kind,
        list_kind = kind .. "List",
        plural = plural,
        path = path,
        limit = 120,
        label_selector = "",
        field_selector = "",
        overtime = "1800",
        version = "",
        continue = "",
        list_watch = list_watch
    }
end

return _M
