local require    = require
local core       = require("apisix.core")
local pcall      = pcall
local loadstring = loadstring

local _M = {
}


function _M.load_script(route, api_ctx)
	local script = route.value.script
	if script == nil then
		return nil
	end

	local loadfun = loadstring(script)

	api_ctx.script_obj = loadfun()
end


function _M.run_script(phase, api_ctx)
    local obj = api_ctx and api_ctx.script_obj or nil

    if not obj then
        return api_ctx
    end

    core.log.info("script_obj", core.json.delay_encode(obj, true))

    local phase_fun = obj[phase]
    if phase_fun then
    	pcall(phase_fun, api_ctx)
    end

    return api_ctx
end


return _M
