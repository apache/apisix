local typeof = require("apimeta.core.typeof")
local log = require("apimeta.core.log")
local tostring = tostring


local _M = {
    log = log,
}


function _M.check_args(args, scheme)
    for k, v in pairs(scheme) do
        if not typeof[v](args[k]) then
            return nil, "args." .. k .. " expect " .. v .. " value but got: ["
                        .. tostring(args[k]) .. "]"
        end
    end

    return true
end


return _M
