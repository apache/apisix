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


local plugins_schema = {
    type = "object"
}


local upstream_schema = {
    type = "object",
    properties = {
        nodes = {
            type = "object"
        },
        type = {
            type = "string",
            enum = {"chash", "roundrobin"}
        },
        id = {
            anyof = {
                {type = "string", minLength = 1, maxLength = 32},
                {type = "integer", minimum = 1}
            }
        }
    },
    required = {"nodes", "type"}
}


_M.route = [[{
    "type": "object",
    "properties": {
        "methods": {
            "type": "array",
            "items": {
                "type": "string",
                "enum": ["GET", "PUT", "POST", "DELETE"]
            },
            "uniqueItems": true
        },
        "plugins": ]] .. rapidjson.encode(plugins_schema) .. [[,
        "upstream": ]] .. rapidjson.encode(upstream_schema) .. [[,
        "uri": {
            "type": "string"
        },
        "service_id": {
            "type": "string"
        },
        "id": {
            "anyOf": [
                {"type": "string", "minLength": 1, "maxLength": 32},
                {"type": "integer", "minimum": 1}
            ]
        }
    },
    "anyOf": [
        { "required": ["plugins", "uri"] },
        { "required": ["upstream", "uri"] },
        { "required": ["service_id", "uri"] }
    ],
    "additionalItems": false
}]]


_M.service = {
    type = "object",
    properties = {
        plugins = plugins_schema,
        upstream = upstream_schema,
    },
    required = {"upstream"}
}


_M.upstream = upstream_schema


return _M
