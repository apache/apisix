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

--- Get configuration information.
--
-- @module core.config_etcd

local table        = require("apisix.core.table")
local config_local = require("apisix.core.config_local")
local config_util  = require("apisix.core.config_util")
local log          = require("apisix.core.log")
local json         = require("apisix.core.json")
local etcd_apisix  = require("apisix.core.etcd")
local core_str     = require("apisix.core.string")
local new_tab      = require("table.new")
local check_schema = require("apisix.core.schema").check
local exiting      = ngx.worker.exiting
local insert_tab   = table.insert
local type         = type
local ipairs       = ipairs
local setmetatable = setmetatable
local ngx_sleep    = require("apisix.core.utils").sleep
local ngx_timer_at = ngx.timer.at
local ngx_time     = ngx.time
local sub_str      = string.sub
local tostring     = tostring
local tonumber     = tonumber
local xpcall       = xpcall
local debug        = debug
local string       = string
local error        = error
local rand         = math.random
local constants    = require("apisix.constants")
local health_check = require("resty.etcd.health_check")


local is_http = ngx.config.subsystem == "http"
local err_etcd_grpc_engine_timeout = "context deadline exceeded"
local err_etcd_grpc_ngx_timeout = "timeout"
local err_etcd_unhealthy_all = "has no healthy etcd endpoint available"
local health_check_shm_name = "etcd-cluster-health-check"
if not is_http then
    health_check_shm_name = health_check_shm_name .. "-stream"
end
local created_obj  = {}
local loaded_configuration = {}


local _M = {
    version = 0.3,
    local_conf = config_local.local_conf,
    clear_local_cache = config_local.clear_cache,
}


local mt = {
    __index = _M,
    __tostring = function(self)
        return " etcd key: " .. self.key
    end
}


local function getkey(etcd_cli, key)
    if not etcd_cli then
        return nil, "not inited"
    end

    local res, err = etcd_cli:readdir(key)
    if not res then
        -- log.error("failed to get key from etcd: ", err)
        return nil, err
    end

    if type(res.body) ~= "table" then
        return nil, "failed to get key from etcd"
    end

    res, err = etcd_apisix.get_format(res, key, true)
    if not res then
        return nil, err
    end

    return res
end


local function readdir(etcd_cli, key, formatter)
    if not etcd_cli then
        return nil, "not inited"
    end

    local res, err = etcd_cli:readdir(key)
    if not res then
        -- log.error("failed to get key from etcd: ", err)
        return nil, err
    end

    if type(res.body) ~= "table" then
        return nil, "failed to read etcd dir"
    end

    res, err = etcd_apisix.get_format(res, key .. '/', true, formatter)
    if not res then
        return nil, err
    end

    return res
end


local function grpc_waitdir(self, etcd_cli, key, modified_index, timeout)
    local watching_stream = self.watching_stream
    if not watching_stream then
        local attr = {}
        attr.start_revision = modified_index
        local opts = {}
        opts.timeout = timeout

        local st, err = etcd_cli:create_grpc_watch_stream(key, attr, opts)
        if not st then
            log.error("create watch stream failed: ", err)
            return nil, err
        end

        log.info("create watch stream for key: ", key, ", modified_index: ", modified_index)

        self.watching_stream = st
        watching_stream = st
    end

    return etcd_cli:read_grpc_watch_stream(watching_stream)
end


local function flush_watching_streams(self)
    local etcd_cli = self.etcd_cli
    if not etcd_cli.use_grpc then
        return
    end

    self.watching_stream = nil
end


local function http_waitdir(etcd_cli, key, modified_index, timeout)
    local opts = {}
    opts.start_revision = modified_index
    opts.timeout = timeout
    opts.need_cancel = true
    local res_func, func_err, http_cli = etcd_cli:watchdir(key, opts)
    if not res_func then
        return nil, func_err
    end

    -- in etcd v3, the 1st res of watch is watch info, useless to us.
    -- try twice to skip create info
    local res, err = res_func()
    if not res or not res.result or not res.result.events then
        res, err = res_func()
    end

    if http_cli then
        local res_cancel, err_cancel = etcd_cli:watchcancel(http_cli)
        if res_cancel == 1 then
            log.info("cancel watch connection success")
        else
            log.error("cancel watch failed: ", err_cancel)
        end
    end

    if not res then
        return nil, err
    end

    if type(res.result) ~= "table" then
        err = "failed to wait etcd dir"
        if res.error and res.error.message then
            err = err .. ": " .. res.error.message
        end
        return nil, err
    end

    return res, err
end


local function waitdir(self)
    local etcd_cli = self.etcd_cli
    local key = self.key
    local modified_index = self.prev_index + 1
    local timeout = self.timeout

    if not etcd_cli then
        return nil, "not inited"
    end

    local res, err
    if etcd_cli.use_grpc then
        res, err = grpc_waitdir(self, etcd_cli, key, modified_index, timeout)
    else
        res, err = http_waitdir(etcd_cli, key, modified_index, timeout)
    end

    if not res then
        -- log.error("failed to get key from etcd: ", err)
        return nil, err
    end

    return etcd_apisix.watch_format(res)
end


local function short_key(self, str)
    return sub_str(str, #self.key + 2)
end


local function load_full_data(self, dir_res, headers)
    local err
    local changed = false

    if self.single_item then
        self.values = new_tab(1, 0)
        self.values_hash = new_tab(0, 1)

        local item = dir_res
        local data_valid = item.value ~= nil

        if data_valid and self.item_schema then
            data_valid, err = check_schema(self.item_schema, item.value)
            if not data_valid then
                log.error("failed to check item data of [", self.key,
                          "] err:", err, " ,val: ", json.encode(item.value))
            end
        end

        if data_valid and self.checker then
            data_valid, err = self.checker(item.value)
            if not data_valid then
                log.error("failed to check item data of [", self.key,
                          "] err:", err, " ,val: ", json.delay_encode(item.value))
            end
        end

        if data_valid then
            changed = true
            insert_tab(self.values, item)
            self.values_hash[self.key] = #self.values

            item.clean_handlers = {}

            if self.filter then
                self.filter(item)
            end
        end

        self:upgrade_version(item.modifiedIndex)

    else
        -- here dir_res maybe res.body.node or res.body.list
        -- we need make values equals to res.body.node.nodes or res.body.list
        local values = (dir_res and dir_res.nodes) or dir_res
        if not values then
            values = {}
        end

        self.values = new_tab(#values, 0)
        self.values_hash = new_tab(0, #values)

        for _, item in ipairs(values) do
            local key = short_key(self, item.key)
            local data_valid = true
            if type(item.value) ~= "table" then
                data_valid = false
                log.error("invalid item data of [", self.key .. "/" .. key,
                          "], val: ", item.value,
                          ", it should be an object")
            end

            if data_valid and self.item_schema then
                data_valid, err = check_schema(self.item_schema, item.value)
                if not data_valid then
                    log.error("failed to check item data of [", self.key,
                              "] err:", err, " ,val: ", json.encode(item.value))
                end
            end

            if data_valid and self.checker then
                data_valid, err = self.checker(item.value)
                if not data_valid then
                    log.error("failed to check item data of [", self.key,
                              "] err:", err, " ,val: ", json.delay_encode(item.value))
                end
            end

            if data_valid then
                changed = true
                insert_tab(self.values, item)
                self.values_hash[key] = #self.values

                item.value.id = key
                item.clean_handlers = {}

                if self.filter then
                    self.filter(item)
                end
            end

            self:upgrade_version(item.modifiedIndex)
        end
    end

    if headers then
        self:upgrade_version(headers["X-Etcd-Index"])
    end

    if changed then
        self.conf_version = self.conf_version + 1
    end

    self.need_reload = false
end


function _M.upgrade_version(self, new_ver)
    new_ver = tonumber(new_ver)
    if not new_ver then
        return
    end

    local pre_index = self.prev_index

    if new_ver <= pre_index then
        return
    end

    self.prev_index = new_ver
    return
end


local function sync_data(self)
    if not self.key then
        return nil, "missing 'key' arguments"
    end

    if self.need_reload then
        flush_watching_streams(self)

        local res, err = readdir(self.etcd_cli, self.key)
        if not res then
            return false, err
        end

        local dir_res, headers = res.body.list or res.body.node or {}, res.headers
        log.debug("readdir key: ", self.key, " res: ",
                  json.delay_encode(dir_res))

        if self.values then
            for i, val in ipairs(self.values) do
                config_util.fire_all_clean_handlers(val)
            end

            self.values = nil
            self.values_hash = nil
        end

        load_full_data(self, dir_res, headers)

        return true
    end

    local dir_res, err = waitdir(self)
    log.info("waitdir key: ", self.key, " prev_index: ", self.prev_index + 1)
    log.info("res: ", json.delay_encode(dir_res, true), ", err: ", err)

    if not dir_res then
        if err == "compacted" then
            self.need_reload = true
            log.warn("waitdir [", self.key, "] err: ", err,
                     ", will read the configuration again via readdir")
            return false
        end

        return false, err
    end

    local res = dir_res.body.node
    local err_msg = dir_res.body.message
    if err_msg then
        return false, err
    end

    if not res then
        return false, err
    end

    local res_copy = res
    -- waitdir will return [res] even for self.single_item = true
    for _, res in ipairs(res_copy) do
        local key
        if self.single_item then
            key = self.key
        else
            key = short_key(self, res.key)
        end

        if res.value and not self.single_item and type(res.value) ~= "table" then
            self:upgrade_version(res.modifiedIndex)
            return false, "invalid item data of [" .. self.key .. "/" .. key
                            .. "], val: " .. res.value
                            .. ", it should be an object"
        end

        if res.value and self.item_schema then
            local ok, err = check_schema(self.item_schema, res.value)
            if not ok then
                self:upgrade_version(res.modifiedIndex)

                return false, "failed to check item data of ["
                                .. self.key .. "] err:" .. err
            end

            if self.checker then
                local ok, err = self.checker(res.value)
                if not ok then
                    self:upgrade_version(res.modifiedIndex)

                    return false, "failed to check item data of ["
                                    .. self.key .. "] err:" .. err
                end
            end
        end

        self:upgrade_version(res.modifiedIndex)

        if res.dir then
            if res.value then
                return false, "todo: support for parsing `dir` response "
                                .. "structures. " .. json.encode(res)
            end
            return false
        end

        local pre_index = self.values_hash[key]
        if pre_index then
            local pre_val = self.values[pre_index]
            if pre_val then
                config_util.fire_all_clean_handlers(pre_val)
            end

            if res.value then
                if not self.single_item then
                    res.value.id = key
                end

                self.values[pre_index] = res
                res.clean_handlers = {}
                log.info("update data by key: ", key)

            else
                self.sync_times = self.sync_times + 1
                self.values[pre_index] = false
                self.values_hash[key] = nil
                log.info("delete data by key: ", key)
            end

        elseif res.value then
            res.clean_handlers = {}
            insert_tab(self.values, res)
            self.values_hash[key] = #self.values
            if not self.single_item then
                res.value.id = key
            end

            log.info("insert data by key: ", key)
        end

        -- avoid space waste
        if self.sync_times > 100 then
            local values_original = table.clone(self.values)
            table.clear(self.values)

            for i = 1, #values_original do
                local val = values_original[i]
                if val then
                    table.insert(self.values, val)
                end
            end

            table.clear(self.values_hash)
            log.info("clear stale data in `values_hash` for key: ", key)

            for i = 1, #self.values do
                key = short_key(self, self.values[i].key)
                self.values_hash[key] = i
            end

            self.sync_times = 0
        end

        -- /plugins' filter need to known self.values when it is called
        -- so the filter should be called after self.values set.
        if self.filter then
            self.filter(res)
        end

        self.conf_version = self.conf_version + 1
    end

    return self.values
end


function _M.get(self, key)
    if not self.values_hash then
        return
    end

    local arr_idx = self.values_hash[tostring(key)]
    if not arr_idx then
        return nil
    end

    return self.values[arr_idx]
end


function _M.getkey(self, key)
    if not self.running then
        return nil, "stopped"
    end

    local local_conf = config_local.local_conf()
    if local_conf and local_conf.etcd and local_conf.etcd.prefix then
        key = local_conf.etcd.prefix .. key
    end

    return getkey(self.etcd_cli, key)
end


local get_etcd
do
    local etcd_cli

    function get_etcd()
        if etcd_cli ~= nil then
            return etcd_cli
        end

        local _, err
        etcd_cli, _, err = etcd_apisix.get_etcd_syncer()
        return etcd_cli, err
    end
end


local function _automatic_fetch(premature, self)
    if premature then
        return
    end

    if not (health_check.conf and health_check.conf.shm_name) then
        -- used for worker processes to synchronize configuration
        local _, err = health_check.init({
            shm_name = health_check_shm_name,
            fail_timeout = self.health_check_timeout,
            max_fails = 3,
            retry = true,
        })
        if err then
            log.warn("fail to create health_check: " .. err)
        end
    end

    local i = 0
    while not exiting() and self.running and i <= 32 do
        i = i + 1

        local ok, err = xpcall(function()
            if not self.etcd_cli then
                local etcd_cli, err = get_etcd()
                if not etcd_cli then
                    error("failed to create etcd instance for key ["
                          .. self.key .. "]: " .. (err or "unknown"))
                end
                self.etcd_cli = etcd_cli
            end

            local ok, err = sync_data(self)
            if err then
                if core_str.find(err, err_etcd_grpc_engine_timeout) or
                   core_str.find(err, err_etcd_grpc_ngx_timeout)
                then
                    err = "timeout"
                end

                if core_str.find(err, err_etcd_unhealthy_all) then
                    local reconnected = false
                    while err and not reconnected and i <= 32 do
                        local backoff_duration, backoff_factor, backoff_step = 1, 2, 6
                        for _ = 1, backoff_step do
                            i = i + 1
                            ngx_sleep(backoff_duration)
                            _, err = sync_data(self)
                            if not err or not string.find(err, err_etcd_unhealthy_all) then
                                log.warn("reconnected to etcd")
                                reconnected = true
                                break
                            end
                            backoff_duration = backoff_duration * backoff_factor
                            log.error("no healthy etcd endpoint available, next retry after "
                                       .. backoff_duration .. "s")
                        end
                    end
                elseif err ~= "timeout" and err ~= "Key not found"
                    and self.last_err ~= err then
                    log.error("failed to fetch data from etcd: ", err, ", ",
                              tostring(self))
                end

                if err ~= self.last_err then
                    self.last_err = err
                    self.last_err_time = ngx_time()
                elseif self.last_err then
                    if ngx_time() - self.last_err_time >= 30 then
                        self.last_err = nil
                    end
                end

                -- etcd watch timeout is an expected error, so there is no need for resync_delay
                if err ~= "timeout" then
                    ngx_sleep(self.resync_delay + rand() * 0.5 * self.resync_delay)
                end
            elseif not ok then
                -- no error. reentry the sync with different state
                ngx_sleep(0.05)
            end

        end, debug.traceback)

        if not ok then
            log.error("failed to fetch data from etcd: ", err, ", ",
                      tostring(self))
            ngx_sleep(self.resync_delay + rand() * 0.5 * self.resync_delay)
            break
        end
    end

    if not exiting() and self.running then
        flush_watching_streams(self)
        ngx_timer_at(0, _automatic_fetch, self)
    end
end

-- for test
_M.test_sync_data = sync_data
_M.test_automatic_fetch = _automatic_fetch
function _M.inject_sync_data(f)
    sync_data = f
end


---
-- Create a new connection to communicate with the control plane.
-- This function should be used in the `init_worker_by_lua` phase.
--
-- @function core.config.new
-- @tparam string key etcd directory to be monitored, e.g. "/routes".
-- @tparam table opts Parameters related to the etcd client connection.
-- The keys in `opts` are as follows:
--  * automatic: whether to get the latest etcd data automatically
--  * item_schema: the jsonschema that checks the value of each item under the **key** directory
--  * filter: the custom function to filter the value of each item under the **key** directory
--  * timeout: the timeout for watch operation, default is 30s
--  * single_item: whether only one item under the **key** directory
--  * checker: the custom function to check the value of each item under the **key** directory
-- @treturn table The etcd client connection.
-- @usage
-- local plugins_conf, err = core.config.new("/custom_dir", {
--    automatic = true,
--    filter = function(item)
--        -- called once before reload for sync data from admin
--    end,
--})
function _M.new(key, opts)
    local local_conf, err = config_local.local_conf()
    if not local_conf then
        return nil, err
    end

    local etcd_conf = local_conf.etcd
    local prefix = etcd_conf.prefix
    local resync_delay = etcd_conf.resync_delay
    if not resync_delay or resync_delay < 0 then
        resync_delay = 5
    end
    local health_check_timeout = etcd_conf.health_check_timeout
    if not health_check_timeout or health_check_timeout < 0 then
        health_check_timeout = 10
    end

    local automatic = opts and opts.automatic
    local item_schema = opts and opts.item_schema
    local filter_fun = opts and opts.filter
    local timeout = opts and opts.timeout
    local single_item = opts and opts.single_item
    local checker = opts and opts.checker

    local obj = setmetatable({
        etcd_cli = nil,
        key = key and prefix .. key,
        automatic = automatic,
        item_schema = item_schema,
        checker = checker,
        sync_times = 0,
        running = true,
        conf_version = 0,
        values = nil,
        need_reload = true,
        watching_stream = nil,
        routes_hash = nil,
        prev_index = 0,
        last_err = nil,
        last_err_time = nil,
        resync_delay = resync_delay,
        health_check_timeout = health_check_timeout,
        timeout = timeout,
        single_item = single_item,
        filter = filter_fun,
    }, mt)

    if automatic then
        if not key then
            return nil, "missing `key` argument"
        end

        if loaded_configuration[key] then
            local res = loaded_configuration[key]
            loaded_configuration[key] = nil -- tried to load

            log.notice("use loaded configuration ", key)

            local dir_res, headers = res.body, res.headers
            load_full_data(obj, dir_res, headers)
        end

        ngx_timer_at(0, _automatic_fetch, obj)

    else
        local etcd_cli, err = get_etcd()
        if not etcd_cli then
            return nil, "failed to start an etcd instance: " .. err
        end
        obj.etcd_cli = etcd_cli
    end

    if key then
        created_obj[key] = obj
    end

    return obj
end


function _M.close(self)
    self.running = false
end


function _M.fetch_created_obj(key)
    return created_obj[key]
end


function _M.server_version(self)
    if not self.running then
        return nil, "stopped"
    end

    local res, err = etcd_apisix.server_version()
    if not res then
        return nil, err
    end

    return res.body
end


local function create_formatter(prefix)
    return function (res)
        res.body.nodes = {}

        local dirs
        if is_http then
            dirs = constants.HTTP_ETCD_DIRECTORY
        else
            dirs = constants.STREAM_ETCD_DIRECTORY
        end

        local curr_dir_data
        local curr_key
        for _, item in ipairs(res.body.kvs) do
            if curr_dir_data then
                if core_str.has_prefix(item.key, curr_key) then
                    table.insert(curr_dir_data, etcd_apisix.kvs_to_node(item))
                    goto CONTINUE
                end

                curr_dir_data = nil
            end

            local key = sub_str(item.key, #prefix + 1)
            if dirs[key] then
                -- single item
                loaded_configuration[key] = {
                    body = etcd_apisix.kvs_to_node(item),
                    headers = res.headers,
                }
            else
                local key = sub_str(item.key, #prefix + 1, #item.key - 1)
                -- ensure the same key hasn't been handled as single item
                if dirs[key] and not loaded_configuration[key] then
                    loaded_configuration[key] = {
                        body = {
                            nodes = {},
                        },
                        headers = res.headers,
                    }
                    curr_dir_data = loaded_configuration[key].body.nodes
                    curr_key = item.key
                end
            end

            ::CONTINUE::
        end

        return res
    end
end


function _M.init()
    local local_conf, err = config_local.local_conf()
    if not local_conf then
        return nil, err
    end

    if table.try_read_attr(local_conf, "apisix", "disable_sync_configuration_during_start") then
        return true
    end

    if local_conf.etcd.use_grpc then
        return true
    end

    -- don't go through proxy during start because the proxy is not available
    local etcd_cli, prefix, err = etcd_apisix.new_without_proxy()
    if not etcd_cli then
        return nil, "failed to start a etcd instance: " .. err
    end

    local res, err = readdir(etcd_cli, prefix, create_formatter(prefix))
    if not res then
        return nil, err
    end

    return true
end


function _M.init_worker()
    local local_conf, err = config_local.local_conf()
    if not local_conf then
        return nil, err
    end

    if table.try_read_attr(local_conf, "apisix", "disable_sync_configuration_during_start") then
        return true
    end

    if not local_conf.etcd.use_grpc then
        return true
    end

    -- don't go through proxy during start because the proxy is not available
    local etcd_cli, prefix, err = etcd_apisix.new_without_proxy()
    if not etcd_cli then
        return nil, "failed to start a etcd instance: " .. err
    end

    local res, err = readdir(etcd_cli, prefix, create_formatter(prefix))
    if not res then
        return nil, err
    end

    return true
end


return _M
