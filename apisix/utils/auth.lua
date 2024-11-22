local _M = {}

function _M.is_running_under_multi_auth(ctx)
    return ctx._plugin_name == "multi-auth"
end

return _M
