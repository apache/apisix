local core = require("apisix.core")
local schema_desc = [[{
    "type": "object",
    "properties": {
        "methods": {
            "type": "array",
            "items": {
                "type": "string",
                "enum": ["GET", "PUT", "POST", "DELETE"]
            }
        },
        "plugins": {
            "type": "object"
        },
        "upstream": {
            "type": "object",
            "properties": {
                "nodes": {
                    "type": "object"
                },
                "type": {
                    "type": "string"
                }
            },
            "required": ["nodes", "type"]
        },
        "uri": {
            "type": "string"
        }
    },
    "required": ["upstream", "uri"]
}]]


local _M = {
    version = 0.1,
}


function _M.schema()
    return schema_desc
end


function _M.put(uri_segs, conf)
    local resource, id = uri_segs[4], uri_segs[5]
    if not id then
        return 400, {error_msg = "missing route id"}
    end

    if not conf then
        return 400, {error_msg = "missing configurations"}
    end

    -- core.log.info("schema: ", core.json.delay_encode(schema_desc))
    local ok, err = core.schema.check(schema_desc, conf)
    if not ok then
        return 400, {error_msg = "invalid configuration: " .. err}
    end

    local key = "/" .. resource .. "/" .. id
    local res, err = core.etcd.set(key, conf)
    if not res then
        core.log.error("failed to put route[", key, "]: ", err)
        return 500, {error_msg = err}
    end

    return res.status, res.body
end


function _M.get(uri_segs)
    local resource, id = uri_segs[4], uri_segs[5]
    local key = "/" .. resource
    if id then
        key = key .. "/" .. id
    end

    local res, err = core.etcd.get(key)
    if not res then
        core.log.error("failed to get route[", key, "]: ", err)
        return 500, {error_msg = err}
    end

    return res.status, res.body
end


function _M.post(uri_segs, conf)
    if not conf then
        return 400, {error_msg = "missing configurations"}
    end

    local ok, err = core.schema.check(schema_desc, conf)
    if not ok then
        return 400, {error_msg = "invalid configuration: " .. err}
    end

    local key = "/" .. uri_segs[4]
    -- core.log.info("key: ", key)
    local res, err = core.etcd.push(key, conf)
    if not res then
        core.log.error("failed to post route[", key, "]: ", err)
        return 500, {error_msg = err}
    end

    return res.status, res.body
end


function _M.delete(uri_segs)
    local resource, id = uri_segs[4], uri_segs[5]
    if not id then
        return 400, {error_msg = "missing route id"}
    end

    local key = "/" .. resource .. "/" .. id
    -- core.log.info("key: ", key)
    local res, err = core.etcd.delete(key)
    if not res then
        core.log.error("failed to delete route[", key, "]: ", err)
        return 500, {error_msg = err}
    end

    return res.status, res.body
end


return _M
