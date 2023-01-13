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

_M.free_list = {}
_M.paid_list = {}
_M.network_list = {}

local networks = {
    -- production
    "eth-mainnet",
    "eth-sepolia",
    "polygon-mainnet",
    "cfx-core",
    "cfx-espace",
    "arb-mainnet",
    "opt-mainnet",
    "scroll-prealpha",
    "ckb-mirana",

    -- staging
    "staging-eth-mainnet",
    "staging-eth-sepolia",
    "staging-polygon-mainnet",
    "staging-cfx-core",
    "staging-cfx-espace",
    "staging-arb-mainnet",
    "staging-opt-mainnet",
    "staging-scroll-prealpha",
    "staging-ckb-mirana",
}

local web3_methods = {
    "web3_clientVersion",
    "web3_sha3",
}

local net_methods = {
    "net_version",
    "net_listening",
    --  "net_peerCount",
}

local eth_methods = {
    "eth_blockNumber",
    "eth_getBlockByHash",
    "eth_getBlockByNumber",
    "eth_getTransactionByHash",
    "eth_getTransactionCount",
    "eth_getTransactionReceipt",
    "eth_getBlockTransactionCountByHash",
    "eth_getBlockTransactionCountByNumber",
    "eth_getTransactionByBlockHashAndIndex",
    "eth_getTransactionByBlockNumberAndIndex",
    "eth_getBlockReceipts",
    "eth_sendRawTransaction",
    "eth_sendPrivateTransaction",
    "eth_cancelPrivateTransaction",
    "eth_getBalance",
    "eth_getStorageAt",
    "eth_getCode",
    --  "eth_accounts",
    "eth_getProof",
    "eth_call",
    "eth_getLogs",
    "eth_protocolVersion",
    "eth_gasPrice",
    "eth_estimateGas",
    "eth_feeHistory",
    "eth_maxPriorityFeePerGas",
    "eth_chainId",
    "eth_getUncleByBlockHashAndIndex",
    "eth_getUncleByBlockNumberAndIndex",
    "eth_getUncleCountByBlockHash",
    "eth_getUncleCountByBlockNumber",
    "eth_getFilterChanges",
    "eth_getFilterLogs",
    "eth_newBlockFilter",
    "eth_newFilter",
    "eth_newPendingTransactionFilter",
    "eth_uninstallFilter",
}

local bor_methods = {
    "bor_getSnapshot",
    "bor_getAuthor",
    "bor_getSnapshotAtHash",
    "bor_getSigners",
    "bor_getSignersAtHash",
    "bor_getCurrentProposer",
    "bor_getCurrentValidators",
    "bor_getRootHash",
}

local erigon_methods = {
    "erigon_getHeaderByHash",
    "erigon_getHeaderByNumber",
    "erigon_getLogsByHash",
    "erigon_forks",
    "erigon_issuance",
    "erigon_GetBlockByTimestamp",
    "erigon_BlockNumber",
}

local db_methods = {
    "db_getHex",
    "db_putHex",
    "db_putString",
    "db_getString",
}

local txpool_methods = {
    "txpool_content",
    "txpool_status",
}

local trace_methods = {
    "trace_call",
    "trace_callMany",
    "trace_rawTransaction",
    "trace_replayBlockTransactions",
    "trace_replayTransaction",
    "trace_block",
    "trace_filter",
    "trace_get",
    "trace_transaction",
}

local debug_methods = {
    --  "debug_accountRange"
    --  "debug_accountAt"
    --  "debug_getModifiedAccountsByNumber",
    --  "debug_getModifiedAccountsByHash",
    --  "debug_storageRangeAt",
    "debug_traceBlockByHash",
    "debug_traceBlockByNumber",
    "debug_traceTransaction",
    "debug_traceCall",
    "debug_traceCallMany",
}


-- local engine_methods = {
--     "engine_newPayloadV1",
--     "engine_forkchoiceUpdatedV1",
--     "engine_getPayloadV1",
--     "engine_exchangeTransitionConfigurationV1",
-- }

local cfx_methods = {
    "cfx_getTransactionByHash",
    "cfx_getBlockByHash",
    "cfx_getBlockByEpochNumber",
    "cfx_getBestBlockHash",
    "cfx_epochNumber",
    "cfx_gasPrice",
    "cfx_getBlocksByEpoch",
    "cfx_getBalance",
    "cfx_getStakingBalance",
    "cfx_getCollateralForStorage",
    "cfx_getAdmin",
    "cfx_getCode",
    "cfx_getStorageAt",
    "cfx_getStorageRoot",
    "cfx_getSponsorInfo",
    "cfx_getNextNonce",
    "cfx_sendRawTransaction",
    "cfx_call",
    "cfx_estimateGasAndCollateral",
    "cfx_getLogs",
    "cfx_getTransactionReceipt",
    "cfx_getAccount",
    "cfx_getInterestRate",
    "cfx_getAccumulateInterestRate",
    "cfx_checkBalanceAgainstTransaction",
    "cfx_getSkippedBlocksByEpoch",
    "cfx_getConfirmationRiskByHash",
    "cfx_getStatus",
    "cfx_clientVersion",
    "cfx_getBlockRewardInfo",
    "cfx_getBlockByHashWithPivotAssumption",
    "cfx_getDepositList",
    "cfx_getVoteList",
    "cfx_getSupplyInfo",
    "cfx_getAccountPendingInfo",
    "cfx_getAccountPendingTransactions",
    "cfx_getBlockByBlockNumber",
    "cfx_getPoSEconomics",
    "cfx_getPoSRewardByEpoch",
    "cfx_getParamsFromVote",
}

local cfx_debug_methods = {
    "cfx_getEpochReceipts",
}

local cfx_pos_methods = {
    "pos_getStatus",
    "pos_getAccount",
    "pos_getCommittee",
    "pos_getBlockByHash",
    "pos_getBlockByNumber",
    "pos_getRewardsByEpoch",
    "pos_getTransactionByNumber",
}

local cfx_trace_methods = {
    "trace_block",
    "trace_transaction",
}

-- local ckb_alert_methods = {
--     "send_alert",
-- }

local ckb_chain_methods = {
    "get_block",
    "get_block_by_number",
    "get_header",
    "get_header_by_number",
    "get_block_filter",
    "get_transaction",
    "get_block_hash",
    "get_tip_header",
    "get_live_cell",
    "get_tip_block_number",
    "get_current_epoch",
    "get_epoch_by_number",
    "get_block_economic_state",
    "get_transaction_proof",
    "verify_transaction_proof",
    "get_fork_block",
    "get_consensus",
    "get_block_median_time",
    "estimate_cycles",
    "get_fee_rate_statics",
}

local ckb_experiment_methods = {
    "dry_run_transaction",
    "calculate_dao_maximum_withdraw",
}

local ckb_indexer_methods = {
    "get_indexer_tip",
    "get_cells",
    "get_transactions",
    "get_cells_capacity",
}

-- local moduleIntegrationTestMethods = {
--     "process_block_without_verify",
--     "truncate",
--     "generate_block",
--     "notify_transaction",
--     "generate_block_with_template",
--     "calculate_dao_field",
-- }

-- local ckbMinerMethods = {
--     "get_block_template",
--     "submit_block",
-- }

local ckb_net_methods = {
    "local_node_info",
    "get_peers",
    -- "get_banned_addresses",
    -- "clear_banned_addresses",
    -- "set_ban",
    "sync_state",
    -- "set_network_active",
    -- "add_node",
    -- "remove_node",
    -- "ping_peers",
}

local ckb_pool_methods = {
    "send_transaction",
    -- "remove_transaction",
    "tx_pool_info",
    -- "clear_tx_pool",
    "get_raw_tx_pool",
    "tx_pool_ready",
}

local ckb_stats_methods = {
    "get_blockchain_info",
    "get_deployments_info",
}

local ckb_subscription_methods = {
    "subscribe",
    "unsubscribe"
}

local function merge_methods(...)
    local methods = {}
    for _, method_list in ipairs({ ... }) do
        for _, method in ipairs(method_list) do
            methods[method] = true
        end
    end
    return methods
end

local function check_access(self, network, method, monthly_quota, default_paid_quota)
    -- check if method is whitelisted
    local isPaid = monthly_quota > default_paid_quota
    local whitelist = isPaid and self.paid_list or self.free_list
    if whitelist[network] and whitelist[network][method] then
        return nil -- access granted
    else
        if isPaid then
            return "Unsupported method: " .. method .. ". See available methods at https://docs.unifra.io"
        else
            return "Method " .. method .. " is only available for paid users. See https://docs.unifra.io"
        end
    end
end

function _M.init()
    _M.network_list = {}
    _M.free_list = {}
    _M.paid_list = {}
    for _, network in ipairs(networks) do
        _M.network_list[network] = true
        if network == "eth-mainnet" or network == "eth-sepolia" or network == "cfx-espace" or
            network == "scroll-prealpha" or network == "staging-eth-mainnet" or network == "staging-eth-sepolia" or
            network == "staging-cfx-espace" or network == "staging-scroll-prealpha" then
            _M.free_list[network] = merge_methods(web3_methods, net_methods, eth_methods)
            _M.paid_list[network] = merge_methods(web3_methods, net_methods, eth_methods, trace_methods)
        elseif network == "arb-mainnet" or network == "opt-mainnet" or
            network == "staging-arb-mainnet" or network == "staging-opt-mainnet" then
            _M.free_list[network] = merge_methods(web3_methods, net_methods, eth_methods)
            _M.paid_list[network] = _M.free_list[network]
        elseif network == "polygon-mainnet" or network == "staging-polygon-mainnet" then
            _M.free_list[network] = merge_methods(web3_methods, net_methods, eth_methods, bor_methods)
            _M.paid_list[network] = merge_methods(web3_methods, net_methods, eth_methods, bor_methods, trace_methods)
        elseif network == "cfx-core" or network == "staging-cfx-core" then
            _M.free_list[network] = merge_methods(cfx_methods, cfx_pos_methods)
            _M.paid_list[network] = merge_methods(cfx_methods, cfx_pos_methods, cfx_trace_methods)
        elseif network == "ckb-mirana" or network == "staging-ckb-mirana" then
            _M.free_list[network] = merge_methods(ckb_chain_methods, ckb_net_methods, ckb_experiment_methods,
                ckb_indexer_methods, ckb_pool_methods, ckb_stats_methods, ckb_subscription_methods)
        else
            error("unknown network: " .. network)
        end
    end
end

function _M.access(conf, ctx)
    local network = ctx.var.router_name
    local method = ctx.var.jsonrpc_method
    local methods = ctx.var.jsonrpc_methods
    local monthly_quota = tonumber(ctx.var.monthly_quota)
    local default_paid_quota = conf.default_paid_quota

    if method == "batch" then
        for _, method in ipairs(methods) do
            local err = check_access(_M, network, method, monthly_quota, default_paid_quota)
            if err then
                return 405, { jsonrpc = "2.0", error = { code = 405, message = err }, id = nil }
            end
        end
    else
        local err = check_access(_M, network, method, monthly_quota, default_paid_quota)
        if err then
            return 405, { jsonrpc = "2.0", error = { code = 405, message = err }, id = nil }
        end
    end
end

return _M
