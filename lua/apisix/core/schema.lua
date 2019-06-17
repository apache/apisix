local json = require('rapidjson')
local schema_validator = json.SchemaValidator
local schema_doc = json.SchemaDocument
local json_doc = json.Document


local _M = {version = 0.1}


-- You can follow this document to write schema:
-- https://github.com/Tencent/rapidjson/blob/master/bin/draft-04/schema
-- rapidjson not supported `format` in draft-04 yet
function _M.check(schema, json)
    local sd = schema_doc(schema)
    local validator = schema_validator(sd)

    local d = json_doc(json)
    return validator:validate(d)
end


local plugins_schema = {
    type = "object"
}


local id_schema = {
    anyOf = {
        {
            type = "string", minLength = 1, maxLength = 32,
            pattern = [[^[0-9]+$]]
        },
        {type = "integer", minimum = 1}
    }
}


local upstream_schema = {
    type = "object",
    properties = {
        nodes = {
            type = "object",
            patternProperties = {
                [".*"] = {
                    type = "integer",
                    minimum = 1,
                }
            },
            minProperties = 1,
        },
        type = {
            type = "string",
            enum = {"chash", "roundrobin"}
        },
        id = id_schema
    },
    required = {"nodes", "type"},
    additionalProperties = false,
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
        "plugins": ]] .. json.encode(plugins_schema) .. [[,
        "upstream": ]] .. json.encode(upstream_schema) .. [[,
        "uri": {
            "type": "string"
        },
        "service_id": ]] .. json.encode(id_schema) .. [[,
        "upstream_id": ]] .. json.encode(id_schema) .. [[,
        "id": ]] .. json.encode(id_schema) .. [[
    },
    "anyOf": [
        {"required": ["plugins", "uri"]},
        {"required": ["upstream", "uri"]},
        {"required": ["upstream_id", "uri"]},
        {"required": ["service_id", "uri"]}
    ],
    "additionalProperties": false
}]]


_M.service = {
    type = "object",
    properties = {
        id = id_schema,
        plugins = plugins_schema,
        upstream = upstream_schema,
        upstream_id = id_schema,
    },
    anyOf = {
        {required = {"upstream"}},
        {required = {"upstream_id"}},
        {required = {"plugins"}},
    },
    additionalProperties = false,
}


_M.upstream = upstream_schema


return _M
