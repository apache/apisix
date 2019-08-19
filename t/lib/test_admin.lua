local http = require("resty.http")
local json = require("cjson.safe")
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
                          .. " expect: " .. tostring(v) .. " got: "
                          .. tostring(data[k])
        end
    end

    return true
end


local methods = {
    [ngx.HTTP_GET    ] = "GET",
    [ngx.HTTP_HEAD   ] = "HEAD",
    [ngx.HTTP_PUT    ] = "PUT",
    [ngx.HTTP_POST   ] = "POST",
    [ngx.HTTP_DELETE ] = "DELETE",
    [ngx.HTTP_OPTIONS] = "OPTIONS",
    [ngx.HTTP_PATCH]   = "PATCH",
}


function _M.test(uri, method, body, pattern)
    if type(body) == "table" then
        body = json.encode(body)
    end

    if type(pattern) == "table" then
        pattern = json.encode(pattern)
    end

    if type(method) == "number" then
        method = methods[method]
    end

    local httpc = http.new()
    -- https://github.com/ledgetech/lua-resty-http
    uri = ngx.var.scheme .. "://" .. ngx.var.server_addr
          .. ":" .. ngx.var.server_port .. uri
    local res = httpc:request_uri(uri,
        {
            method = method,
            body = body,
            keepalive = false,
            headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded",
            },
        }
    )

    if res.status >= 300 then
        return res.status, res.body
    end

    if pattern == nil then
        return res.status, "passed", res.body
    end

    local res_data = json.decode(res.body)
    if type(pattern) == "string" then
        pattern = json.decode(pattern)
    end

    local ok, err = com_tab(pattern, res_data)
    if not ok then
        return 500, "failed, " .. err, res_data
    end

    return 200, "passed", res_data
end


function _M.read_file(path)
    local f = assert(io.open(path, "rb"))
    local cert = f:read("*all")
    f:close()
    return cert
end


return _M
