local core = require("apisix.core")
local schema_plugin = require("apisix.admin.plugins").check_schema
local type = type


local _M = {
    version = 0.1,
}


local function check_conf(conf)
    if not conf then
        return nil, {error_msg = "missing configurations"}
    end

    core.log.info("schema: ", core.json.delay_encode(core.schema.global_rule))
    core.log.info("conf  : ", core.json.delay_encode(conf))
    local ok, err = core.schema.check(core.schema.global_rule, conf)
    if not ok then
        return nil, {error_msg = "invalid configuration: " .. err}
    end

    local ok, err = schema_plugin(conf.plugins)
    if not ok then
        return nil, {error_msg = err}
    end

    return true
end


function _M.put(_, conf)
    local ok, err = check_conf(conf)
    if not ok then
        return 400, err
    end

    local key = "/global_rules/1"
    local res, err = core.etcd.set(key, conf)
    if not res then
        core.log.error("failed to put global rule[", key, "]: ", err)
        return 500, {error_msg = err}
    end

    return res.status, res.body
end


function _M.get()
    local key = "/global_rules/1"
    local res, err = core.etcd.get(key)
    if not res then
        core.log.error("failed to get global rule[", key, "]: ", err)
        return 500, {error_msg = err}
    end

    return res.status, res.body
end


function _M.delete()
    local key = "/global_rules/1"
    -- core.log.info("key: ", key)
    local res, err = core.etcd.delete(key)
    if not res then
        core.log.error("failed to delete global rule[", key, "]: ", err)
        return 500, {error_msg = err}
    end

    return res.status, res.body
end


function _M.patch(_, conf, sub_path)
    if not sub_path then
        return 400, {error_msg = "missing sub-path"}
    end

    if not conf then
        return 400, {error_msg = "missing new configuration"}
    end

    local key = "/global_rules/1"
    local res_old, err = core.etcd.get(key)
    if not res_old then
        core.log.error("failed to get global rule [", key, "]: ", err)
        return 500, {error_msg = err}
    end

    if res_old.status ~= 200 then
        return res_old.status, res_old.body
    end
    core.log.info("key: ", key, " old value: ",
                  core.json.delay_encode(res_old, true))

    local node_value = res_old.body.node.value
    local sub_value = node_value
    local sub_paths = core.utils.split_uri(sub_path)
    for i = 1, #sub_paths - 1 do
        local sub_name = sub_paths[i]
        if sub_value[sub_name] == nil then
            sub_value[sub_name] = {}
        end

        sub_value = sub_value[sub_name]

        if type(sub_value) ~= "table" then
            return 400, "invalid sub-path: /"
                        .. core.table.concat(sub_paths, 1, i)
        end
    end

    if type(sub_value) ~= "table" then
        return 400, "invalid sub-path: /" .. sub_path
    end

    local sub_name = sub_paths[#sub_paths]
    if sub_name and sub_name ~= "" then
        sub_value[sub_name] = conf
    else
        node_value = conf
    end
    core.log.info("new conf: ", core.json.delay_encode(node_value, true))

    local ok, err = check_conf(node_value)
    if not ok then
        return 400, err
    end

    -- TODO: this is not safe, we need to use compare-set
    local res, err = core.etcd.set(key, node_value)
    if not res then
        core.log.error("failed to set new global rule[", key, "]: ", err)
        return 500, {error_msg = err}
    end

    return res.status, res.body
end


return _M
