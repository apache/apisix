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
local pcall   = pcall
local require = require
local ipairs  = ipairs
local type    = type
local core    = require("apisix.core")
local resource = require("apisix.admin.resource")
local plugin_encrypt_conf = require("apisix.plugin").encrypt_conf
local ticket_record = require("apisix.plugins.ssl-session-ticket.record")
local ticket_generator = require("apisix.plugins.ssl-session-ticket.generator")

local injected_mark = "injected metadata_schema"
local ticket_name = ticket_record.name

-- how core.etcd.atomic_set and atomic_delete report a failed comparison
local changed_errs = {
    ["value changed before overwritten"] = true,
    ["value changed before deleted"] = true,
}


local function validate_plugin(name)
    local pkg_name = "apisix.plugins." .. name
    local ok, plugin_object = pcall(require, pkg_name)
    if ok then
        return true, plugin_object
    end

    pkg_name = "apisix.stream.plugins." .. name
    return pcall(require, pkg_name)
end


local function inject_metadata_schema(plugin_object)
    if not plugin_object.metadata_schema then
        plugin_object.metadata_schema = {
            type = "object",
            ['$comment'] = injected_mark,
            properties = {},
        }
    end
end


local function check_conf(plugin_name, conf)
    if not plugin_name then
        return nil, {error_msg = "missing plugin name"}
    end

    if plugin_name == ticket_name then
        -- a complete record, as given in a standalone configuration; the
        -- errors never contain key material
        local ok, err = ticket_record.check_standalone(conf)
        if not ok then
            return nil, {error_msg = "invalid configuration: " .. err}
        end

        return plugin_name
    end

    local ok, plugin_object = validate_plugin(plugin_name)
    if not ok then
        return nil, {error_msg = "invalid plugin name"}
    end

    inject_metadata_schema(plugin_object)

    local schema = plugin_object.metadata_schema

    local ok, err
    if schema['$comment'] == injected_mark
      -- check_schema is not required. If missing, fallback to check schema directly
      or not plugin_object.check_schema
    then
        ok, err = core.schema.check(schema, conf)
    else
        ok, err = plugin_object.check_schema(conf, core.schema.TYPE_METADATA)
    end

    if not ok then
        return nil, {error_msg = "invalid configuration: " .. err}
    end

    return plugin_name
end

local function encrypt_conf(plugin_name, conf)
    if not plugin_name then
        -- This situation shouldn't happen according to the execution order.
        core.log.info("missing plugin name")
        return
    end

    local ok, plugin_object = validate_plugin(plugin_name)
    if not ok then
        -- This situation shouldn't happen according to the execution order.
        core.log.info("invalid plugin name")
        return
    end

    inject_metadata_schema(plugin_object)

    local schema = plugin_object.metadata_schema
    -- encrypt whenever the plugin has a real metadata schema; do not gate on
    -- check_schema, or a plugin that validates via core.schema.check would leak
    -- its metadata encrypt_fields in plaintext
    if schema['$comment'] ~= injected_mark then
        plugin_encrypt_conf(plugin_name, conf, core.schema.TYPE_METADATA)
    end
end


local _M = resource.new({
    name = "plugin_metadata",
    kind = "plugin_metadata",
    schema = core.schema.plugin_metadata,
    checker = check_conf,
    encrypt_conf = encrypt_conf,
    unsupported_methods = {"post", "patch"}
})


-- The ssl-session-ticket metadata only carries the complete set of keys. The
-- local policy decides whether the Admin API may write it at all, and APISIX
-- adds the `origin` envelope itself. Writes are atomic against the revision
-- that was read, and no response ever contains key material.


local function redact_node(node)
    if type(node) == "table" and type(node.value) == "table" then
        node.value = ticket_record.redact(node.value)
    end
end


local function redact(body)
    if type(body) ~= "table" then
        return
    end

    if type(body.node) == "table" then
        if type(body.node.nodes) == "table" then
            for _, node in ipairs(body.node.nodes) do
                if type(node.value) == "table" and node.value.id == ticket_name then
                    redact_node(node)
                end
            end

        else
            redact_node(body.node)
        end
    end

    if type(body.list) == "table" then
        for _, item in ipairs(body.list) do
            if type(item.value) == "table" and item.value.id == ticket_name then
                redact_node(item)
            end
        end
    end
end


local function external_policy()
    local policy, err = ticket_record.policy()
    if not policy then
        return nil, 503, {error_msg = err}
    end

    if policy.key_source ~= "external" then
        return nil, 409, {
            error_msg = "the keys of " .. ticket_name .. " are maintained by the built-in "
                        .. "generator because plugin_attr." .. ticket_name
                        .. ".key_source is " .. policy.key_source .. "; set it to external "
                        .. "to manage the keys through the Admin API"
        }
    end

    -- the nodes must agree on the policy before anything is written
    local conflict, desc = ticket_generator.policy_conflict(
                                ticket_record.policy_fingerprint(policy))
    if conflict == nil then
        return nil, 503, {error_msg = desc}
    end

    if conflict then
        return nil, 409, {error_msg = "writes are paused: " .. desc}
    end

    return policy
end


local function put_ticket_keys(conf, args)
    if args and args.ttl then
        return 400, {error_msg = "ttl is not supported for " .. ticket_name}
    end

    local policy, code, body = external_policy()
    if not policy then
        return code, body
    end

    if conf == nil then
        return 400, {error_msg = "missing configurations"}
    end

    local keys, err = ticket_record.check_request(conf)
    if not keys then
        return 400, {error_msg = "invalid configuration: " .. err}
    end

    local origin = {
        source = "external",
        disabled = not policy.enabled,
        policy = ticket_record.policy_fingerprint(policy),
    }

    local res, get_err = core.etcd.get(ticket_record.etcd_key)
    if not res then
        core.log.error("failed to get ", ticket_name, " metadata from etcd: ", get_err)
        return 503, {error_msg = get_err}
    end

    local mod_revision = 0
    if res.status == 200 then
        mod_revision = res.body.node.modifiedIndex
        local cur = ticket_record.parse(res.body.node.value)
        if cur and cur.origin.source == origin.source and cur.origin.disabled == origin.disabled
           and cur.origin.policy == origin.policy and ticket_record.same_keys(cur.keys, keys)
        then
            -- the same keys in the same order: no write, no new revision
            redact(res.body)
            return 200, res.body
        end

    elseif res.status ~= 404 then
        return 503, {error_msg = "failed to get " .. ticket_name .. " metadata, status: "
                                 .. res.status}
    end

    local value
    value, err = ticket_record.build(keys, origin)
    if not value then
        core.log.error("failed to build ", ticket_name, " metadata: ", err)
        return 503, {error_msg = err}
    end

    local set_res, set_err = core.etcd.atomic_set(ticket_record.etcd_key, value, nil,
                                                  mod_revision)
    if not set_res then
        if changed_errs[set_err] then
            return 409, {error_msg = ticket_name .. " metadata was changed concurrently, "
                                     .. "retry the request"}
        end

        core.log.error("failed to put ", ticket_name, " metadata to etcd: ", set_err)
        return 503, {error_msg = set_err}
    end

    set_res.body.responses = nil
    redact(set_res.body)
    return mod_revision == 0 and 201 or 200, set_res.body
end


local function delete_ticket_keys()
    local policy, code, body = external_policy()
    if not policy then
        return code, body
    end

    local res, err = core.etcd.get(ticket_record.etcd_key)
    if not res then
        core.log.error("failed to get ", ticket_name, " metadata from etcd: ", err)
        return 503, {error_msg = err}
    end

    if res.status ~= 200 then
        return res.status, res.body
    end

    local del_res, del_err = core.etcd.atomic_delete(ticket_record.etcd_key,
                                                     res.body.node.modifiedIndex)
    if not del_res then
        if changed_errs[del_err] then
            return 409, {error_msg = ticket_name .. " metadata was changed concurrently, "
                                     .. "retry the request"}
        end

        core.log.error("failed to delete ", ticket_name, " metadata in etcd: ", del_err)
        return 503, {error_msg = del_err}
    end

    del_res.body.responses = nil
    return del_res.status, del_res.body
end


function _M:get(id, conf, sub_path)
    local code, body = resource.get(self, id, conf, sub_path)
    if id == nil or id == ticket_name then
        redact(body)
    end

    return code, body
end


function _M:put(id, conf, sub_path, args)
    if id == ticket_name then
        return put_ticket_keys(conf, args)
    end

    return resource.put(self, id, conf, sub_path, args)
end


function _M:delete(id, conf, sub_path, uri_args)
    if id == ticket_name then
        return delete_ticket_keys()
    end

    return resource.delete(self, id, conf, sub_path, uri_args)
end


-- the body of the ssl-session-ticket metadata carries key material: never echo
-- it or log it, not even when it is not valid JSON
function _M.sensitive_body(id)
    return id == ticket_name
end


return _M
