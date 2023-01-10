local core = require("apisix.core")

local plugin_name = "whitelist"

local schema = {
    type = "object",
    properties = {
        default_paid_quota = {
            description = "default paid quota",
            type = "integer",
            default = 1000000,
        },
    },
    required = { "default_paid_quota" },
}

local _M = {
    version = 0.1,
    priority = 1900,
    name = plugin_name,
    schema = schema,

}
local networks = {
    "eth-mainnet",
    "eth-rinkeby",
    "eth-ropsten",
    "eth-kovan",
}

local web3_methods = {
    "web3_clientVersion",
    "web3_sha3",
}

local net_methods = {
    "net_version",
    "net_peerCount",
}

local eth_methods = {
    "eth_blockNumber",
}

local trace_methods = {
    "trace_block",

}

local bor_methods = {}

local function merge_methods(...)
    local methods = {}
    for _, method_list in ipairs({ ... }) do
        for _, method in ipairs(method_list) do
            methods[method] = true
        end
    end
    return methods
end

local function new(self)
    local free_list = {}
    local paid_list = {}
    local network_list = {}

    for _, network in ipairs(networks) do
        network_list[network] = true
        if network == "eth-mainnet" or network == "eth-sepolia" or network == "cfx-espace" or
            network == "scroll-prealpha" or network == "staging-eth-mainnet" or network == "staging-eth-sepolia" or
            network == "staging-cfx-espace" or network == "staging-scroll-prealpha" then
            free_list[network] = merge_methods(web3_methods, net_methods, eth_methods)
            paid_list[network] = merge_methods(web3_methods, net_methods, eth_methods, trace_methods)
        elseif network == "arb-mainnet" or network == "opt-mainnet" or
            network == "staging-arb-mainnet" or network == "staging-opt-mainnet" then
            free_list[network] = merge_methods(web3_methods, net_methods, eth_methods)
            paid_list[network] = free_list[network]
        elseif network == "polygon-mainnet" or network == "staging-polygon-mainnet" then
            free_list[network] = merge_methods(web3_methods, net_methods, eth_methods, bor_methods)
            paid_list[network] = merge_methods(web3_methods, net_methods, eth_methods, bor_methods, trace_methods)
        end
    end

    return setmetatable({
        free_list = free_list,
        paid_list = paid_list,
        network_list = network_list,
    }, { __index = self })
end

local function check_access(self, network, method, monthly_quota, default_paid_quota)
    -- check if method is whitelisted
    local isPaid = monthly_quota > default_paid_quota
    local whitelist = isPaid and self.paid_list or self.free_list
    if whitelist[network] and whitelist[network][method] then
        return nil -- access granted
    else
        if isPaid then
            return "unsupported method"
        else
            return "unpaid method"
        end
    end
end

function _M.access(conf, ctx)
    local network = ctx.var["router_name"]
    local method = ctx.var.jsonrpc_method
    local methods = ctx.var.jsonrpc_methods
    local monthly_quota = ctx.var.monthly_quota
    local default_paid_quota = conf.default_paid_quota

    local self = new(_M)
    local err = check_access(self, network, method, monthly_quota, default_paid_quota)
    if err then
        if err == "unsupported method" then
            return ngx.exit(ngx.HTTP_BAD_REQUEST)
        elseif err == "unpaid method" then
            return ngx.exit(ngx.HTTP_PAYMENT_REQUIRED)
        else
            return ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
        end
    end
end

return _M
