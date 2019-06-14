local rapidjson = require('rapidjson')
local rapidjson_schema_validator = rapidjson.SchemaValidator
local rapidjson_schema_doc = rapidjson.SchemaDocument
local rapidjson_doc = rapidjson.Document


local cached_sd = require("apisix.core.lrucache").new({count = 1000, ttl = 0})


local _M = {version = 0.1}


local function create_validator(schema)
    local sd = rapidjson_schema_doc(schema)
    local validator = rapidjson_schema_validator(sd)

    -- bug: we have to use a table to store the `validator` first,
    --   if we returned the `validator` directyly, we will get
    --   some error like this:
    --
    --   attempt to call method 'validate' (a nil value)
    return {validator}
end


-- You can follow this document to write schema:
-- https://github.com/Tencent/rapidjson/blob/master/bin/draft-04/schema
-- rapidjson not supported `format` in draft-04 yet
function _M.check(schema, json)
    local validator = cached_sd(schema, nil, create_validator, schema)[1]

    local d = rapidjson_doc(json)
    return validator:validate(d)
end


local plugins_schema = [[
    "plugins": {
        "type": "object"
    }
]]


local upstream_schema = [[
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
    }
]]


_M.route = [[{
    "type": "object",
    "properties": {
        "methods": {
            "type": "array",
            "items": {
                "type": "string",
                "enum": ["GET", "PUT", "POST", "DELETE"]
                "uniqueItems" = true,
            }
        },
        ]] .. plugins_schema .. [[,
        ]] .. upstream_schema .. [[,
        "uri": {
            "type": "string"
        }
    },
    "required": ["upstream", "uri"]
}]]


_M.service = [[{
    "type": "object",
    "properties": {
        ]] .. plugins_schema .. [[,
        ]] .. upstream_schema .. [[
    },
    "required": ["upstream"]
}]]


return _M
