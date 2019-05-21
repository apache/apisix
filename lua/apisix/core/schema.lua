-- todo: change to https://github.com/iresty/ljsonschema

local typeof = require("apisix.core.typeof")
local tostring = tostring
local pairs = pairs


local _M = {version = 0.1}


function _M.check_args(args, schema)
    for k, v in pairs(schema) do
        if not typeof[v](args[k]) then
            return nil, "args." .. k .. " expect " .. v .. " value but got: ["
                        .. tostring(args[k]) .. "]"
        end
    end

    return true
end

return _M
