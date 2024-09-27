local ltn12 = require("ltn12")
local http  = require("socket.http")
local https = require("ssl.https")

local str_sub      = string.sub
local table_concat = table.concat

local _M = {}


function _M.request(url, yaml_conf)
    local response_body = {}
    local single_request = false
    if type(url) == "string" then
        url = {
            url = url,
            method = "GET",
            sink = ltn12.sink.table(response_body),
        }
        single_request = true
    end

    local res, code

    if str_sub(url.url, 1, 8) == "https://" then
        local verify = "peer"
        if yaml_conf.etcd.tls then
            local cfg = yaml_conf.etcd.tls

            if cfg.verify == false then
                verify = "none"
            end

            url.certificate = cfg.cert
            url.key = cfg.key

            local apisix_ssl = yaml_conf.apisix.ssl
            if apisix_ssl and apisix_ssl.ssl_trusted_certificate then
                url.cafile = apisix_ssl.ssl_trusted_certificate
            end
        end

        url.verify = verify
        res, code = https.request(url)
    else

        res, code = http.request(url)
    end

    -- In case of failure, request returns nil followed by an error message.
    -- Else the first return value is the response body
    -- and followed by the response status code.
    if single_request and res ~= nil then
        return table_concat(response_body), code
    end

    return res, code
end

return _M
