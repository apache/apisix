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
local apisix_plugin = require("apisix.plugin")
local ngx_time = ngx.time
local tonumber = tonumber
local tostring = tostring
local ipairs = ipairs
local pairs = pairs
local type = type


local _M = {}


local function inject_timestamp(conf, prev_conf, patch_conf)
    if not conf.create_time then
        if prev_conf and (prev_conf.node or prev_conf.list).value.create_time then
            conf.create_time = (prev_conf.node or prev_conf.list).value.create_time
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


local function decrypt_value(value, schema_type)
    if type(value) ~= "table" then
        return
    end

    if schema_type == core.schema.TYPE_METADATA then
        local marked, err = apisix_plugin.decrypt_marked_metadata(value)
        if err then
            return err
        end

        if apisix_plugin.enable_gde() then
            apisix_plugin.decrypt_conf(value.id, value, schema_type, marked)
        end
        return nil, marked
    end

    local plugins = value.plugins
    if type(plugins) ~= "table" then
        return
    end

    local marked, err = apisix_plugin.decrypt_marked_plugins(plugins)
    if err then
        return err
    end

    if apisix_plugin.enable_gde() then
        for name, conf in pairs(plugins) do
            apisix_plugin.decrypt_conf(name, conf, schema_type, marked)
        end
    end

    return nil, marked
end


-- Decrypt the plugin confs, or the plugin metadata, of an etcd response body in
-- place: values carrying the encryption marker always, `encrypt_fields` when
-- data encryption is enabled. A resource with a marked value that fails to
-- decrypt is left as stored, and the error of the first one is returned. For a
-- single node, the positions decrypted through the marker are returned too.
function _M.decrypt_params(body, schema_type)
    if body.list then
        local first_err
        for _, item in ipairs(body.list) do
            local err = decrypt_value(item.value, schema_type)
            if err and not first_err then
                first_err = err
            end
        end
        return first_err
    end

    return decrypt_value(body.node and body.node.value, schema_type)
end


-- Encrypt again with the marker the values `decrypt_params` decrypted through
-- it and that are still unchanged, so that they stay encrypted at rest.
function _M.restore_marked(marked)
    if not marked then
        return
    end

    for conf, keys in pairs(marked) do
        for k, plain in pairs(keys) do
            if conf[k] == plain then
                conf[k] = core.data_encryption.encrypt_with_marker(plain)
            end
        end
    end
end


local function find_reserved_prefix(conf)
    for k, v in pairs(conf) do
        local tv = type(v)
        if tv == "string" then
            if core.data_encryption.has_reserved_prefix(v) then
                return tostring(k)
            end

        elseif tv == "table" then
            local path = find_reserved_prefix(v)
            if path then
                return tostring(k) .. "." .. path
            end
        end
    end
end


local function reserved_prefix_err(path)
    return "invalid value of " .. path .. ": the prefix \""
           .. core.data_encryption.RESERVED_PREFIX .. "\" is reserved for encrypted values"
end


-- Reject user input that would be taken for an encrypted value: a string
-- starting with the reserved prefix anywhere the data plane decrypts marked
-- values, i.e. the plugin confs and the plugin metadata. `sub_path` is the
-- PATCH sub path `conf` is written to.
function _M.check_reserved_prefix(res_name, conf, sub_path)
    if res_name == "plugin_metadata" then
        if type(conf) == "table" then
            local path = find_reserved_prefix(conf)
            if path then
                return reserved_prefix_err(path)
            end
        end
        return
    end

    if sub_path and sub_path ~= "" then
        local segs = core.utils.split_uri(sub_path)
        if segs[1] == "plugins" then
            local base = core.table.concat(segs, ".")
            if core.data_encryption.has_reserved_prefix(conf) then
                return reserved_prefix_err(base)
            end

            if type(conf) == "table" then
                local path = find_reserved_prefix(conf)
                if path then
                    return reserved_prefix_err(base .. "." .. path)
                end
            end
            return
        end
    end

    if type(conf) == "table" and type(conf.plugins) == "table" then
        local path = find_reserved_prefix(conf.plugins)
        if path then
            return reserved_prefix_err("plugins." .. path)
        end
    end
end


return _M
