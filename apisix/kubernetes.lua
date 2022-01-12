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
local core = require("apisix.core")
local http = require("resty.http")

local _constants = {
    ErrorEvent = "ERROR",
    AddedEvent = "ADDED",
    ModifiedEvent = "MODIFIED",
    DeletedEvent = "DELETED",
    BookmarkEvent = "BOOKMARK",
    ListDrive = "list",
    WatchDrive = "watch",
    ErrorGone = 410,
}

local _apiserver = {
    schema = "",
    host = "",
    port = "",
    token = ""
}

local empty_table = {}

local function list(httpc, informer)
    local res, err = httpc:request({
        path = informer.path,
        query = informer:list_query(),
        headers = {
            ["Host"] = _apiserver.host .. ":" .. _apiserver.port,
            ["Authorization"] = "Bearer " .. _apiserver.token,
            ["Accept"] = "application/json",
            ["Connection"] = "keep-alive"
        }
    })

    core.log.info("--raw=" .. informer.path .. "?" .. informer:list_query())

    if not res then
        return false, "RequestError", err or ""
    end

    if res.status ~= 200 then
        return false, res.reason, res:read_body() or ""
    end
    local body, err = res:read_body()
    if err then
        return false, "ReadBodyError", err
    end

    local data, _ = core.json.decode(body)
    if not data or data.kind ~= informer.list_kind then
        return false, "UnexpectedBody", body
    end

    informer.version = data.metadata.resourceVersion

    if informer.on_added ~= nil then
        for _, item in ipairs(data.items or empty_table) do
            informer:on_added(item, _constants.ListDrive)
        end
    end

    informer.continue = data.metadata.continue
    if informer.continue ~= nil and informer.continue ~= "" then
        list(httpc, informer)
    end

    return true, "Success", ""
end

local function watch(httpc, informer)
    local max_watch_times = 5
    for _ = 0, max_watch_times do
        local watch_seconds = 1800 + math.random(9, 999)
        informer.overtime = watch_seconds
        local http_seconds = watch_seconds + 120
        httpc:set_timeouts(2000, 3000, http_seconds * 1000)

        local res, err = httpc:request({
            path = informer.path,
            query = informer:watch_query(),
            headers = {
                ["Host"] = _apiserver.host .. ":" .. _apiserver.port,
                ["Authorization"] = "Bearer " .. _apiserver.token,
                ["Accept"] = "application/json",
                ["Connection"] = "keep-alive"
            }
        })

        core.log.info("--raw=" .. informer.path .. "?" .. informer:watch_query())

        if err then
            return false, "RequestError", err
        end

        if res.status ~= 200 then
            return false, res.reason, res:read_body() or ""
        end

        local remainder_body = ""
        local body
        local reader = res.body_reader
        local gmatch_iterator
        local captures
        local captured_size = 0

        while true do
            body, err = reader()
            if err then
                return false, "ReadBodyError", err
            end

            if not body then
                break
            end

            if #remainder_body ~= 0 then
                body = remainder_body .. body
            end

            gmatch_iterator, err = ngx.re.gmatch(body, "{\"type\":.*}\n", "jao")
            if not gmatch_iterator then
                return false, "GmatchError", err
            end

            captures, err = gmatch_iterator()

            if err then
                return false, "GmatchError", err
            end

            if not captures then
                break
            end

            captured_size = captured_size + #captures[0]
            local v, _ = core.json.decode(captures[0])

            if not v or not v.object then
                return false, "UnexpectedBody", captures[0]
            end

            local type = v.type
            if type == _constants.ErrorEvent then
                if v.object.code == _constants.ErrorGone then
                    return true, "Success", nil
                end
                return false, "UnexpectedBody", captures[0]
            end

            local object = v.object
            informer.version = object.metadata.resourceVersion

            if type == _constants.AddedEvent then
                if informer.on_added ~= nil then
                    informer:on_added(object, _constants.WatchDrive)
                end
            elseif type == _constants.DeletedEvent then
                if informer.on_deleted ~= nil then
                    informer:on_deleted(object)
                end
            elseif type == _constants.ModifiedEvent then
                if informer.on_modified ~= nil then
                    informer:on_modified(object)
                end
                -- elseif type == _constants.BookmarkEvent then
                --    do nothing
            end

            if captured_size == #body then
                remainder_body = ""
            elseif captured_size == 0 then
                remainder_body = body
            else
                remainder_body = string.sub(body, captured_size + 1)
            end
        end
    end
    return true, "Success", ""
end

local _informer_factory = {
}

function _informer_factory.new(group, version, kind, plural, namespace)
    local _t = {
        kind = kind,
        list_kind = kind .. "List",
        plural = plural,
        path = "",
        version = "",
        continue = "",
        overtime = "1800",
        limit = 120,
        label_selector = "",
        field_selector = "",
    }

    if group == "" then
        _t.path = _t.path .. "/api/" .. version
    else
        _t.path = _t.path .. "/apis/" .. group .. "/" .. version
    end

    if namespace ~= "" then
        _t.path = _t.path .. "/namespace/" .. namespace
    end
    _t.path = _t.path .. "/" .. plural

    function _t.list_query(self)
        local uri = "limit=" .. self.limit

        if self.continue ~= nil and self.continue ~= "" then
            uri = uri .. "&continue=" .. self.continue
        end

        if self.label_selector and self.label_selector ~= "" then
            uri = uri .. "&labelSelector=" .. self.label_selector
        end

        if self.field_selector and self.field_selector ~= "" then
            uri = uri .. "&fieldSelector=" .. self.field_selector
        end

        return uri
    end

    function _t.watch_query(self)
        local uri = "watch=true&allowWatchBookmarks=true&timeoutSeconds=" .. self.overtime

        if self.version ~= nil and self.version ~= "" then
            uri = uri .. "&resourceVersion=" .. self.version
        end

        if self.label_selector and self.label_selector ~= "" then
            uri = uri .. "&labelSelector=" .. self.label_selector
        end

        if self.field_selector and self.field_selector ~= "" then
            uri = uri .. "&fieldSelector=" .. self.field_selector
        end

        return uri
    end

    function _t.list_watch(self)
        local ok
        local reason, message
        local httpc = http.new()

        self.fetch_state = "connecting"
        core.log.info("begin to connect ", _apiserver.host, ":", _apiserver.port)

        ok, message = httpc:connect({
            scheme = _apiserver.schema,
            host = _apiserver.host,
            port = _apiserver.port,
            ssl_verify = false
        })

        if not ok then
            self.fetch_state = "connecting"
            core.log.error("connect apiserver failed , _apiserver.host: ", _apiserver.host,
                    ", _apiserver.port: ", _apiserver.port, ", message : ", message)
            return false
        end

        core.log.info("begin to list ", self.kind)
        self.fetch_state = "listing"
        if self.pre_List ~= nil then
            self:pre_list()
        end

        ok, reason, message = list(httpc, self)
        if not ok then
            self.fetch_state = "list failed"
            core.log.error("list failed, kind: ", self.kind,
                    ", reason: ", reason, ", message : ", message)
            return false
        end

        self.fetch_state = "list finished"
        if self.post_List ~= nil then
            self:post_list()
        end

        core.log.info("begin to watch ", self.kind)
        self.fetch_state = "watching"
        ok, reason, message = watch(httpc, self)
        if not ok then
            self.fetch_state = "watch failed"
            core.log.error("watch failed, kind: ", self.kind,
                    ", reason: ", reason, ", message : ", message)
            return false
        end

        self.fetch_state = "watch finished"
        return true
    end

    return _t
end

return {
    version = "0.0.1",
    informer_factory = _informer_factory,
    apiserver = _apiserver,
    __index = _constants
}
