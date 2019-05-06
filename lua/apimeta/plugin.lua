local typeof = require("apimeta.comm.typeof")
local log = require("apimeta.comm.log")


local _M = {
    log = log,
}


function _M.check_args(arg, scheme)
    for k, v in pairs(scheme) do
        if not typeof[v](arg[k]) then
            return nil, "key [" .. k .. "] should be a " .. v
        end
    end

    return true
end


return _M
