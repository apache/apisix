local rapidjson = require('rapidjson')
local rapidjson_schema_validator = rapidjson.SchemaValidator
local rapidjson_schema_doc = rapidjson.SchemaDocument
local rapidjson_doc = rapidjson.Document
local cached_sd = require("apisix.core.lrucache").new({count = 1000, ttl = 0})


local _M = {version = 0.1}


local function create_validator(schema)
    local sd = rapidjson_schema_doc(schema)
    local validator = rapidjson_schema_validator(sd)
    -- log.info("type: ", type(validator))

    -- only support to cache lua table object
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


return _M
