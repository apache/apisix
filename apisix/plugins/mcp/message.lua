local _M = {}

function _M.initialize_response(id, result)
    return {
        jsonrpc = "2.0",
        id = id,
        result = result,
    }
end

return _M
