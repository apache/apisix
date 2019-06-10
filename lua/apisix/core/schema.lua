local rapidjson_schema_validator = require('rapidjson').SchemaValidator
local rapidjson_schema_doc = require('rapidjson').SchemaDocument
local rapidjson_doc = require('rapidjson').Document


local _M = {version = 0.1}

local schema_sd = {}

-- You can follow this document to write schema:
-- https://github.com/Tencent/rapidjson/blob/master/bin/draft-04/schema
-- rapidjson not supported `format` in draft-04 yet
function _M.check_args(schema, json)
    local sd = schema_sd[schema]
    if not sd then
        sd = rapidjson_schema_doc(schema)
        schema_sd[schema] = sd
    end
    local validator = rapidjson_schema_validator(sd)
    local d = rapidjson_doc(json)
    return validator:validate(d)
end

return _M
