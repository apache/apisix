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
local config_local = require("apisix.core.config_local")
local yaml         = require("tinyyaml")
local log          = require("apisix.core.log")
local json         = require("apisix.core.json")
local process      = require("ngx.process")
local new_tab      = require("table.new")
local check_schema = require("apisix.core.schema").check
local profile      = require("apisix.core.profile")
local lfs          = require("lfs")
local exiting      = ngx.worker.exiting
local insert_tab   = table.insert
local type         = type
local ipairs       = ipairs
local setmetatable = setmetatable
local ngx_sleep    = ngx.sleep
local ngx_timer_at = ngx.timer.at
local ngx_time     = ngx.time
local sub_str      = string.sub
local tostring     = tostring
local pcall        = pcall
local io           = io
local ngx          = ngx
local re_find      = ngx.re.find
local apisix_yaml_path = profile:yaml_path("apisix")
local created_obj  = {}


local _M = {
    version = 0.2,
    local_conf = config_local.local_conf,
    clear_local_cache = config_local.clear_cache,
}


local mt = {
    __index = _M,
    __tostring = function(self)
        return "apisix.yaml key: " .. (self.key or "")
    end
}


    local apisix_yaml
    local apisix_yaml_ctime
local function read_apisix_yaml(pre_mtime)
    local attributes, err = lfs.attributes(apisix_yaml_path)
    if not attributes then
        log.error("failed to fetch ", apisix_yaml_path, " attributes: ", err)
        return
    end

    -- log.info("change: ", json.encode(attributes))
    local last_change_time = attributes.change
    if apisix_yaml_ctime == last_change_time then
        return
    end

    local f, err = io.open(apisix_yaml_path, "r")
    if not f then
        log.error("failed to open file ", apisix_yaml_path, " : ", err)
        return
    end

    local found_end_flag
    for i = 1, 10 do
        f:seek('end', -i)

        local end_flag = f:read("*a")
        -- log.info(i, " flag: ", end_flag)
        if re_find(end_flag, [[#END\s*]], "jo") then
            found_end_flag = true
            break
        end
    end

    if not found_end_flag then
        f:close()
        log.warn("missing valid end flag in file ", apisix_yaml_path)
        return
    end

    f:seek('set')
    local yaml_config = f:read("*a")
    f:close()

    local apisix_yaml_new = yaml.parse(yaml_config)
    if not apisix_yaml_new then
        log.error("failed to parse the content of file " .. apisix_yaml_path)
        return
    end

    apisix_yaml = apisix_yaml_new
    apisix_yaml_ctime = last_change_time
end


local function sync_data(self)
    if not self.key then
        return nil, "missing 'key' arguments"
    end

    if not apisix_yaml_ctime then
        log.warn("wait for more time")
        return nil, "failed to read local file " .. apisix_yaml_path
    end

    if self.conf_version == apisix_yaml_ctime then
        return true
    end

    local items = apisix_yaml[self.key]
    log.info(self.key, " items: ", json.delay_encode(items))
    if not items then
        self.values = new_tab(8, 0)
        self.values_hash = new_tab(0, 8)
        self.conf_version = apisix_yaml_ctime
        return true
    end

    if self.values then
        for _, item in ipairs(self.values) do
            if item.clean_handlers then
                for _, clean_handler in ipairs(item.clean_handlers) do
                    clean_handler(item)
                end
                item.clean_handlers = nil
            end
        end
        self.values = nil
    end

    self.values = new_tab(#items, 0)
    self.values_hash = new_tab(0, #items)

    local err
    for i, item in ipairs(items) do
        local id = tostring(i)
        local data_valid = true
        if type(item) ~= "table" then
            data_valid = false
            log.error("invalid item data of [", self.key .. "/" .. id,
                        "], val: ", json.delay_encode(item),
                        ", it shoud be a object")
        end

        local key = item.id or "arr_" .. i
        local conf_item = {value = item, modifiedIndex = apisix_yaml_ctime,
                           key = "/" .. self.key .. "/" .. key}

        if data_valid and self.item_schema then
            data_valid, err = check_schema(self.item_schema, item)
            if not data_valid then
                log.error("failed to check item data of [", self.key,
                          "] err:", err, " ,val: ", json.delay_encode(item))
            end
        end

        if data_valid then
            insert_tab(self.values, conf_item)
            local item_id = conf_item.value.id or self.key .. "#" .. id
            item_id = tostring(item_id)
            self.values_hash[item_id] = #self.values
            conf_item.value.id = item_id
            conf_item.clean_handlers = {}

            if self.filter then
                self.filter(conf_item)
            end
        end
    end

    self.conf_version = apisix_yaml_ctime
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

    local i = 0
    while not exiting() and self.running and i <= 32 do
        i = i + 1
        local ok, ok2, err = pcall(sync_data, self)
        if not ok then
            err = ok2
            log.error("failed to fetch data from local file " .. apisix_yaml_path .. ": ",
                      err, ", ", tostring(self))
            ngx_sleep(3)
            break

        elseif not ok2 and err then
            if err ~= "timeout" and err ~= "Key not found"
               and self.last_err ~= err then
                log.error("failed to fetch data from local file " .. apisix_yaml_path .. ": ",
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

    -- like /routes and /upstreams, remove first char `/`
    if key then
        key = sub_str(key, 2)
    end

    local obj = setmetatable({
        automatic = automatic,
        item_schema = item_schema,
        sync_times = 0,
        running = true,
        conf_version = 0,
        values = nil,
        routes_hash = nil,
        prev_index = nil,
        last_err = nil,
        last_err_time = nil,
        key = key,
        filter = filter_fun,
    }, mt)

    if automatic then
        if not key then
            return nil, "missing `key` argument"
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
    return "apisix.yaml " .. _M.version
end


function _M.fetch_created_obj(key)
    return created_obj[key]
end


function _M.init_worker()
    if process.type() ~= "worker" and process.type() ~= "single" then
        return
    end

    read_apisix_yaml()
    ngx.timer.every(1, read_apisix_yaml)
end


return _M
