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

--- Get configuration information in Stand-alone mode.
--
-- @module core.config_yaml

local config_local = require("apisix.core.config_local")
local config_util  = require("apisix.core.config_util")
local yaml         = require("lyaml")
local log          = require("apisix.core.log")
local json         = require("apisix.core.json")
local new_tab      = require("table.new")
local check_schema = require("apisix.core.schema").check
local profile      = require("apisix.core.profile")
local lfs          = require("lfs")
local file         = require("apisix.cli.file")
local exiting      = ngx.worker.exiting
local insert_tab   = table.insert
local type         = type
local ipairs       = ipairs
local setmetatable = setmetatable
local ngx_sleep    = require("apisix.core.utils").sleep
local ngx_timer_at = ngx.timer.at
local ngx_time     = ngx.time
local ngx_shared   = ngx.shared
local sub_str      = string.sub
local tostring     = tostring
local pcall        = pcall
local io           = io
local ngx          = ngx
local re_find      = ngx.re.find
local process      = require("ngx.process")
local worker_id    = ngx.worker.id
local apisix_yaml_path = profile:yaml_path("apisix")
local apisix_json_path = ngx.re.sub(apisix_yaml_path, [[\.yaml$]], ".json", "jo")
local created_obj  = {}
local shared_dict
local status_report_shared_dict_name = "status-report"

local _M = {
    version = 0.2,
    local_conf = config_local.local_conf,
    clear_local_cache = config_local.clear_cache,

    ERR_NO_SHARED_DICT = "failed prepare standalone config shared dict, this will degrade "..
                    "to event broadcasting, and if a worker crashes, the configuration "..
                    "cannot be restored from other workers and shared dict"
}

local file_configs = {
    {path = apisix_yaml_path, type = "yaml"},
    {path = apisix_json_path, type = "json"}
}
-- file_type: 'yaml' or 'json'
local file_type
-- file_path: apisix_yaml_path or apisix_json_path
local file_path

local mt = {
    __index = _M,
    __tostring = function(self)
        return "apisix." .. file_type .. " key: " .. (self.key or "")
    end
}

local apisix_config
local apisix_config_mtime

local function sync_status_to_shdict(status)
    if process.type() ~= "worker" then
        return
    end
    local status_shdict = ngx.shared[status_report_shared_dict_name]
    if not status_shdict then
        return
    end
    local id = worker_id()
    log.info("sync status to shared dict, id: ", id, " status: ", status)
    status_shdict:set(id, status)
end


local function update_config(table, conf_version)
    if not table then
        log.error("failed update config: empty table")
        return
    end

    local ok, err = file.resolve_conf_var(table)
    if not ok then
        log.error("failed to resolve variables:" .. err)
        return
    end

    apisix_config = table
    sync_status_to_shdict(true)
    apisix_config_mtime = conf_version
end
_M._update_config = update_config


local function is_use_admin_api()
    local local_conf, _ = config_local.local_conf()
    return local_conf and local_conf.apisix and local_conf.apisix.enable_admin
end


local function read_apisix_config(premature, pre_mtime)
    if premature then
        return
    end
    local last_modification_time
    local paths_str = ""
    for i, config in ipairs(file_configs) do
        local attributes, err = lfs.attributes(config.path)
        if attributes then
            file_type = config.type
            file_path = config.path

            last_modification_time = attributes.modification
            if apisix_config_mtime == last_modification_time then
                return
            end

            break
        else
            paths_str = paths_str .. config.path
            if i < #file_configs then
                paths_str = paths_str .. ", "
            end
            log.warn("failed to fetch ", config.path, " attributes: ", err)
        end
    end

    if not file_path or not file_type then
        log.error("Faild to find any configuration file with path ", paths_str)
        return
    end

    local f, err = io.open(file_path, "r")
    if not f then
        log.error("failed to open file ", file_path, " : ", err)
        return
    end

    local apisix_config_new
    if file_type == "yaml" then
        f:seek('end', -10)
        local end_flag = f:read("*a")
        local found_end_flag = re_find(end_flag, [[#END\s*$]], "jo")

        if not found_end_flag then
            f:close()
            log.warn("missing valid end flag in file ", file_path)
            return
        end

        f:seek('set')
        local raw_config = f:read("*a")
        f:close()

        apisix_config_new = yaml.load(raw_config)
    elseif file_type == "json" then
        local raw_config = f:read("*a")
        f:close()

        apisix_config_new, err = json.decode(raw_config)
        if err then
            log.error("failed to decode json: ", err, " raw_config: ", raw_config)
            return
        end
    end

    if not apisix_config_new then
        log.error("failed to parse the content of file " .. file_path)
        return
    end

    update_config(apisix_config_new, last_modification_time)

    log.warn("config file ", file_path, " reloaded.")
end


local function sync_data(self)
    if not self.key then
        return nil, "missing 'key' arguments"
    end

    local conf_version
    if is_use_admin_api() then
        conf_version = apisix_config[self.conf_version_key] or 0
    else
        if not apisix_config_mtime then
            log.warn("wait for more time")
            return nil, "failed to read local file " .. file_path
        end
        conf_version = apisix_config_mtime
    end

    if not conf_version or conf_version == self.conf_version then
        return true
    end

    local items = apisix_config[self.key]
    if not items then
        self.values = new_tab(8, 0)
        self.values_hash = new_tab(0, 8)
        self.conf_version = conf_version
        return true
    end

    if self.values and #self.values > 0 then
        if is_use_admin_api() then
            -- filter self.values to retain only those whose IDs exist in the new items list.
            local exist_values = new_tab(8, 0)
            self.values_hash = new_tab(0, 8)

            local exist_items = {}
            for _, item in ipairs(items) do
                exist_items[tostring(item.id)] = true
            end
            -- remove objects that exist in the self.values but do not exist in the new items.
            -- for removed items, trigger cleanup handlers.
            for _, item in ipairs(self.values) do
                local id = item.value.id
                if not exist_items[id]  then
                    config_util.fire_all_clean_handlers(item)
                else
                    insert_tab(exist_values, item)
                    self.values_hash[id] = #exist_values
                end
            end
            self.values = exist_values
        else
            for _, item in ipairs(self.values) do
                config_util.fire_all_clean_handlers(item)
            end
            self.values = nil
        end
    end

    if self.single_item then
        -- treat items as a single item
        self.values = new_tab(1, 0)
        self.values_hash = new_tab(0, 1)

        local item = items
        local modifiedIndex = item.modifiedIndex or conf_version
        local conf_item = {value = item, modifiedIndex = modifiedIndex,
                           key = "/" .. self.key}

        local data_valid = true
        local err
        if self.item_schema then
            data_valid, err = check_schema(self.item_schema, item)
            if not data_valid then
                log.error("failed to check item data of [", self.key,
                          "] err:", err, " ,val: ", json.delay_encode(item))
            end

            if data_valid and self.checker then
                -- TODO: An opts table should be used
                -- as different checkers may use different parameters
                data_valid, err = self.checker(item, conf_item.key)
                if not data_valid then
                    log.error("failed to check item data of [", self.key,
                              "] err:", err, " ,val: ", json.delay_encode(item))
                end
            end
        end

        if data_valid then
            insert_tab(self.values, conf_item)
            self.values_hash[self.key] = #self.values
            conf_item.clean_handlers = {}

            if self.filter then
                self.filter(conf_item)
            end
        end

    else
        if not self.values then
            self.values = new_tab(8, 0)
            self.values_hash = new_tab(0, 8)
        end

        local err
        for i, item in ipairs(items) do
            local idx = tostring(i)
            local data_valid = true
            if type(item) ~= "table" then
                data_valid = false
                log.error("invalid item data of [", self.key .. "/" .. idx,
                          "], val: ", json.delay_encode(item),
                          ", it should be an object")
            end

            local id = item.id or item.username or ("arr_" .. idx)
            local modifiedIndex = item.modifiedIndex or conf_version
            local conf_item = {value = item, modifiedIndex = modifiedIndex,
                            key = "/" .. self.key .. "/" .. id}

            if data_valid and self.item_schema then
                data_valid, err = check_schema(self.item_schema, item)
                if not data_valid then
                    log.error("failed to check item data of [", self.key,
                              "] err:", err, " ,val: ", json.delay_encode(item))
                end
            end

            if data_valid and self.checker then
                data_valid, err = self.checker(item, conf_item.key)
                if not data_valid then
                    log.error("failed to check item data of [", self.key,
                              "] err:", err, " ,val: ", json.delay_encode(item))
                end
            end

            if data_valid then
                local item_id = tostring(id)
                local pre_index = self.values_hash[item_id]
                if pre_index then
                    -- remove the old item
                    local pre_val = self.values[pre_index]
                    if pre_val and
                        (not item.modifiedIndex or pre_val.modifiedIndex ~= item.modifiedIndex) then
                        config_util.fire_all_clean_handlers(pre_val)
                        self.values[pre_index] = conf_item
                        conf_item.value.id = item_id
                        conf_item.clean_handlers = {}
                    end
                else
                    insert_tab(self.values, conf_item)
                    self.values_hash[item_id] = #self.values
                    conf_item.value.id = item_id
                    conf_item.clean_handlers = {}
                end

                if self.filter then
                    self.filter(conf_item)
                end
            end
        end
    end

    self.conf_version = conf_version
    return true
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


local function _automatic_fetch(premature, self)
    if premature then
        return
    end

    -- the _automatic_fetch is only called in the timer, and according to the
    -- documentation, ngx.shared.DICT.get can be executed there.
    -- if the file's global variables have not yet been assigned values,
    -- we can assume that the worker has not been initialized yet and try to
    -- read any old data that may be present from the shared dict
    -- try load from shared dict only on first startup, otherwise use event mechanism
    if is_use_admin_api() and not shared_dict then
        log.info("try to load config from shared dict")

        local config, err
        shared_dict = ngx_shared["standalone-config"] -- init shared dict in current worker
        if not shared_dict then
            log.error("failed to read config from shared dict: shared dict not found")
            goto SKIP_SHARED_DICT
        end
        config, err = shared_dict:get("config")
        if not config then
            if err then -- if the key does not exist, the return values are both nil
                log.error("failed to read config from shared dict: ", err)
            end
            log.info("no config found in shared dict")
            goto SKIP_SHARED_DICT
        end
        log.info("startup config loaded from shared dict: ", config)

        config, err = json.decode(tostring(config))
        if not config then
            log.error("failed to decode config from shared dict: ", err)
            goto SKIP_SHARED_DICT
        end
        _M._update_config(config)
        log.info("config loaded from shared dict")

        ::SKIP_SHARED_DICT::
        if not shared_dict then
            log.crit(_M.ERR_NO_SHARED_DICT)

            -- fill that value to make the worker not try to read from shared dict again
            shared_dict = "error"
        end
    end

    local i = 0
    while not exiting() and self.running and i <= 32 do
        i = i + 1
        local ok, ok2, err = pcall(sync_data, self)
        if not ok then
            err = ok2
            log.error("failed to fetch data from local file " .. file_path .. ": ",
                      err, ", ", tostring(self))
            ngx_sleep(3)
            break

        elseif not ok2 and err then
            if err ~= "timeout" and err ~= "Key not found"
               and self.last_err ~= err then
                log.error("failed to fetch data from local file " .. file_path .. ": ",
                          err, ", ", tostring(self))
            end

            if err ~= self.last_err then
                self.last_err = err
                self.last_err_time = ngx_time()
            else
                if ngx_time() - self.last_err_time >= 30 then
                    self.last_err = nil
                end
            end
            ngx_sleep(0.5)

        elseif not ok2 then
            ngx_sleep(0.05)

        else
            ngx_sleep(0.1)
        end
    end

    if not exiting() and self.running then
        ngx_timer_at(0, _automatic_fetch, self)
    end
end


function _M.new(key, opts)
    local local_conf, err = config_local.local_conf()
    if not local_conf then
        return nil, err
    end

    local automatic = opts and opts.automatic
    local item_schema = opts and opts.item_schema
    local filter_fun = opts and opts.filter
    local single_item = opts and opts.single_item
    local checker = opts and opts.checker

    -- like /routes and /upstreams, remove first char `/`
    if key then
        key = sub_str(key, 2)
    end

    local obj = setmetatable({
        automatic = automatic,
        item_schema = item_schema,
        checker = checker,
        sync_times = 0,
        running = true,
        conf_version = 0,
        values = nil,
        routes_hash = nil,
        prev_index = nil,
        last_err = nil,
        last_err_time = nil,
        key = key,
        conf_version_key = key and key .. "_conf_version",
        single_item = single_item,
        filter = filter_fun,
    }, mt)

    if automatic then
        if not key then
            return nil, "missing `key` argument"
        end

        local ok, ok2, err = pcall(sync_data, obj)
        if not ok then
            err = ok2
        end

        if err then
            log.error("failed to fetch data from local file ", file_path, ": ",
                      err, ", ", key)
        end

        ngx_timer_at(0, _automatic_fetch, obj)
    end

    if key then
        created_obj[key] = obj
    end

    return obj
end


function _M.close(self)
    self.running = false
end


function _M.server_version(self)
    return "apisix." .. file_type .. _M.version
end


function _M.fetch_created_obj(key)
    return created_obj[sub_str(key, 2)]
end


function _M.fetch_all_created_obj()
    return created_obj
end


function _M.init()
    if is_use_admin_api() then
        return true
    end

    read_apisix_config()
    return true
end


function _M.init_worker()
    sync_status_to_shdict(false)
    if is_use_admin_api() then
        apisix_config = {}
        apisix_config_mtime = 0
        return true
    end

    -- sync data in each non-master process
    ngx.timer.every(1, read_apisix_config)

    return true
end


return _M
