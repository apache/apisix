-- Copyright (C) Yuansheng Wang

local get_request = require("resty.core.base").get_request
local r3router = require("resty.r3")
local core     = require("apisix.core")
local ngx_ssl  = require("ngx.ssl")
local ffi      = require("ffi")
local errmsg   = ffi.new("char *[1]")
local C        = ffi.C
local ipairs   = ipairs
local type     = type
local error    = error
local ffi_string = ffi.string
local ssl


ffi.cdef[[
int ngx_http_lua_ffi_cert_pem_to_der(const unsigned char *pem,
    size_t pem_len, unsigned char *der, char **err);
int ngx_http_lua_ffi_ssl_set_der_certificate(void *r,
    const char *data, size_t len, char **err);
]]


local _M = {
    version = 0.1,
    server_name = ngx_ssl.server_name,
}


    local empty_tab = {}
    local route_items
local function create_r3_router(ssl_items)
    local ssl_items = ssl_items or empty_tab

    route_items = core.table.new(#ssl_items, 0)
    local idx = 0

    for _, ssl in ipairs(ssl_items) do
        if type(ssl) == "table" then
            local sni = ssl.value.sni:reverse()
            if sni:sub(#sni) == "*" then
                sni = sni:sub(1, #sni - 1) .. "{prefix:.*}"
            end

            idx = idx + 1
            route_items[idx] = {
                path = sni,
                handler = function (params, api_ctx)
                    api_ctx.matched_ssl = ssl
                end
            }
        end
    end

    core.log.info("route items: ", core.json.delay_encode(route_items, true))
    local r3 = r3router.new(route_items)
    r3:compile()
    return r3
end


local function set_pem_ssl_key(cert, pkey)
    local r = get_request()
    if r == nil then
        return false, "no request found"
    end

    local out = ffi.new("char [?]", #cert)
    local rc = C.ngx_http_lua_ffi_cert_pem_to_der(cert, #cert, out, errmsg)
    if rc < 1 then
        return false, "failed to parse PEM cert: " .. ffi_string(errmsg[0])
    end

    local cert_der = ffi_string(out, rc)
    local rc = C.ngx_http_lua_ffi_ssl_set_der_certificate(r, cert_der,
                    #cert_der, errmsg)
    if rc ~= 0 then
        return false, "failed to set DER cert: " .. ffi_string(errmsg[0])
    end

    out = ffi.new("char [?]", #pkey)
    local rc = C.ngx_http_lua_ffi_priv_key_pem_to_der(pkey, #pkey, out, errmsg)
    if rc < 1 then
        return false, "failed to parse PEM priv key: " .. ffi_string(errmsg[0])
    end

    local pkey_der = ffi_string(out, rc)

    local rc = C.ngx_http_lua_ffi_ssl_set_der_private_key(r, pkey_der,
                    #pkey_der, errmsg)
    if rc ~= 0 then
        return false, "failed to set DER priv key: " .. ffi_string(errmsg[0])
    end

    return true
end


function _M.match(api_ctx)
    ngx_ssl.clear_certs()

    local r3, err = core.lrucache.global("/ssl", ssl.conf_version,
                        create_r3_router, ssl.values)
    if not r3 then
        return false, "failed to fetch ssl router: " .. err
    end

    local sni
    sni, err = ngx_ssl.server_name()
    if type(sni) ~= "string" then
        return false, "failed to fetch SNI: " .. (err or "not found")
    end

    core.log.debug("sni: ", sni)
    local ok = r3:dispatch2(nil, sni:reverse(), nil, api_ctx)
    if not ok then
        core.log.warn("not found any valid sni configuration")
        return false
    end

    local matched_ssl = api_ctx.matched_ssl
    core.log.info("debug: ", core.json.delay_encode(matched_ssl, true))
    ok, err = set_pem_ssl_key(matched_ssl.value.cert, matched_ssl.value.key)
    if not ok then
        return false, err
    end

    return true
end


function _M.init_worker()
    local err
    ssl, err = core.config.new("/ssl", {
                        automatic = true,
                        item_schema = core.schema.ssl
                    })
    if not ssl then
        error("failed to create etcd instance for fetching ssl: " .. err)
    end
end


return _M
