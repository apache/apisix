local core = require("apisix.core")
local http = require("resty.http")
local cjson = require("cjson")

local plugin_name = "proxy-chain"


local schema = {
    type = "object",
    properties = {
        services = {
            type = "array",
            items = {
                type = "object",
                properties = {
                    uri = { type = "string", minLength = 1 },
                    method = { type = "string", enum = {"GET", "POST", "PUT", "DELETE"}, default = "POST" }
                },
                required = {"uri"}
            },
            minItems = 1
        },
        token_header = { type = "string" } 
    },
    required = {"services"}
}

local _M = {
    version = 0.1,
    priority = 1000,
    name = plugin_name,
    schema = schema,
    description = "A plugin to chain multiple service requests and merge their responses."
}

function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end

function _M.access(conf, ctx)
    
    ngx.req.read_body()
    local original_body = ngx.req.get_body_data()
    local original_data = {}

    core.log.info("Original body: ", original_body or "nil")
    if original_body and original_body ~= "" then
        local success, decoded = pcall(cjson.decode, original_body)
        if success then
            original_data = decoded
        else
            core.log.warn("Invalid JSON in original body: ", original_body)
        end
    end

    local uri_args = ngx.req.get_uri_args()
    for k, v in pairs(uri_args) do
        original_data[k] = v
    end

    
    local headers = ngx.req.get_headers()
    local auth_header
    if conf.token_header then
        local token = headers[conf.token_header] or headers[conf.token_header:lower()] or ""
        if token == "" then
            core.log.info("No token found in header: ", conf.token_header, ", falling back to Authorization")
            token = headers["Authorization"] or headers["authorization"] or ""
            if token ~= "" then
                token = token:gsub("^Bearer%s+", "")
            end
        end
        if token ~= "" then
            core.log.info("Token extracted from ", conf.token_header, ": ", token)
            auth_header = "Bearer " .. token
        else
            core.log.info("No token provided in ", conf.token_header, " or Authorization, proceeding without auth")
        end
    else
        local token = headers["Authorization"] or headers["authorization"] or ""
        if token ~= "" then
            token = token:gsub("^Bearer%s+", "")
            core.log.info("Token extracted from Authorization: ", token)
            auth_header = "Bearer " .. token
        else
            core.log.info("No token_header specified and no Authorization provided, proceeding without auth")
        end
    end

    local merged_data = core.table.deepcopy(original_data)

    
    for i, service in ipairs(conf.services) do
        local httpc = http.new()
        local service_headers = {
            ["Content-Type"] = "application/json",
            ["Accept"] = "*/*"
        }
        if auth_header then
            service_headers["Authorization"] = auth_header
        end

        local res, err = httpc:request_uri(service.uri, {
            method = service.method,
            body = cjson.encode(merged_data),
            headers = service_headers
        })

        if not res then
            core.log.error("Failed to call service ", service.uri, ": ", err)
            return 500, { error = "Failed to call service: " .. service.uri }
        end

        if res.status ~= 200 then
            core.log.error("Service ", service.uri, " returned non-200 status: ", res.status, " body: ", res.body or "nil")
            return res.status, { error = "Service error", body = res.body }
        end

        core.log.info("Response from ", service.uri, ": ", res.body or "nil")

        local service_data = {}
        if res.body and res.body ~= "" then
            local success, decoded = pcall(cjson.decode, res.body)
            if success then
                service_data = decoded
            else
                core.log.error("Invalid JSON in response from ", service.uri, ": ", res.body)
                return 500, { error = "Invalid JSON in response from " .. service.uri }
            end
        end

        for k, v in pairs(service_data) do
            merged_data[k] = v
        end
    end

    local new_body = cjson.encode(merged_data)
    core.log.info("Merged data sent to upstream: ", new_body)

    ctx.proxy_chain_response = merged_data
    ngx.req.set_body_data(new_body)
    if auth_header then
        ngx.req.set_header("Authorization", auth_header)
    end
end

return _M