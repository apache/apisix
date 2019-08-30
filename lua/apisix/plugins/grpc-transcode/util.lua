local json     = require("apisix.core.json")
local pb       = require("pb")
local ngx      = ngx
local pairs    = pairs
local ipairs   = ipairs
local string   = string
local tonumber = tonumber
local type     = type


local _M = {version = 0.1}


function _M.find_method(protos, service, method)
    for k, loaded in pairs(protos) do
        if type(loaded) == 'table' then
            local package = loaded.package
            for _, s in ipairs(loaded.service or {}) do
                if package .. "." .. s.name == service then
                    for _, m in ipairs(s.method) do
                        if m.name == method then
                            return m
                        end
                    end
                end
            end
        end
    end

    return nil
end


local function get_from_request(name, kind)
    local request_table
    if ngx.req.get_method() == "POST" then
        if string.find(ngx.req.get_headers()["Content-Type"] or "",
                       "application/json", true) then
            request_table = json.decode(ngx.req.get_body_data())
        else
            request_table = ngx.req.get_post_args()
        end
    else
        request_table = ngx.req.get_uri_args()
    end

    local prefix = kind:sub(1, 3)
    if prefix == "str" then
        return request_table[name] or nil
    end

    if prefix == "int" then
        if request_table[name] then
            return tonumber(request_table[name])
        end
    end

    return nil
end


function _M.map_message(field, default_values)
    if not pb.type(field) then
        return nil, "Field " .. field .. " is not defined"
    end

    local request = {}
    local sub, err
    for name, _, field_type in pb.fields(field) do
        if field_type:sub(1, 1) == "." then
            sub, err = _M.map_message(field_type, default_values)
            if err then
                return nil, err
            end
            request[name] = sub
        else
            request[name] = get_from_request(name, field_type)
                                or default_values[name] or nil
        end
    end
    return request
end


return _M
