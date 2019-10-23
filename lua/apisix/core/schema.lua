local jsonschema = require('resty.jsonschema')
local lrucache = require("apisix.core.lrucache")

local cached_validator = lrucache.new({count = 1000, ttl = 0})
local opts = {match_pattern = ngx.re.find}

local _M = {version = 0.3}


local function create_validator(schema)
    -- local code = jsonschema.generate_validator_code(schema, opts)
    -- local file2=io.output("/tmp/2.txt")
    -- file2:write(code)
    -- file2:close()
    return jsonschema.generate_validator(schema, opts)
end


function _M.check(schema, json)
    local validator = cached_validator(schema, nil, create_validator, schema)
    return validator(json)
end


return _M
