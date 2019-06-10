local rapidjson_doc = require('rapidjson').Document


local _M = {version = 0.1}


-- You can follow this document to write schema:
-- https://github.com/Tencent/rapidjson/blob/master/bin/draft-04/schema
-- rapidjson not supported `format` in draft-04 yet
function _M.check_args(validator, json)
    local d = rapidjson_doc(json)
    return validator:validate(d)
end

return _M
