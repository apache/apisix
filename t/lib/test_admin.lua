local json = require("cjson")
local dir_names = {}


local _M = {}


local function com_tab(pattern, data, deep)
    deep = deep or 1

    for k, v in pairs(pattern) do
        dir_names[deep] = k

        if type(v) == "table" then
            local ok, err = com_tab(v, data[k], deep + 1)
            if not ok then
                return false, err
            end

        elseif v ~= data[k] then
            return false, "path: " .. table.concat(dir_names, "->", 1, deep)
                          .. " expect: " .. v .. " got: " .. data[k]
        end
    end

    return true
end


function _M.test(uri, method, body, pattern)
    local res = ngx.location.capture(
        uri,
        {
            method = ngx.HTTP_PUT,
            body = body
        }
    )

    if res.status >= 300 or pattern == nil then
        return res.status, res.body
    end

    local ok, err = com_tab(json.decode(pattern), json.decode(res.body))
    if not ok then
        return 200, "failed, " .. err
    end

    return 200, "passed"
end


return _M
