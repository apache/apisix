--[[
    节点状态
    详见：
    http://nginx.org/en/docs/http/ngx_http_stub_status_module.html
--]]
local core = require("apisix.core")
local ngx = ngx
local re_gmatch = ngx.re.gmatch
local plugin_name = "node-status"
local apisix_id = core.id.get()
local ipairs = ipairs


local _M = {
    version = 0.1,
    priority = 1000,        -- TODO: add a type field, may be a good idea
    name = plugin_name,
}


local ngx_status = {}
local ngx_statu_items = {
    "active", "accepted", "handled", "total",
    "reading", "writing", "waiting"
}

--[[
    从 etcd 中收集数据
--]]
local function collect()
    core.log.info("try to collect node status from etcd: ",
                  "/node_status/" .. apisix_id)
    local res, err = core.etcd.get("/node_status/" .. apisix_id)
    if not res then
        return 500, {error = err}
    end

    return res.status, res.body
end

--[[
    向 etcd 上报数据
--]]
local function run_loop()
    -- 提取nginx状态，该请求是在配置文件中配置的，启用了的openresty的http_stub_status_module模块
    -- 详细请查看配置文件
    local res, err = core.http.request_self("/apisix/nginx_status", {
                                                keepalive = false,
                                            })
    if not res then
        if err then
            return core.log.error("failed to fetch nginx status: ", err)
        end
        return
    end

    if res.status ~= 200 then
        core.log.error("failed to fetch nginx status, response code: ",
                       res.status)
        return
    end

    -- Active connections: 2
    -- server accepts handled requests
    --   26 26 84
    -- Reading: 0 Writing: 1 Waiting: 1

    local iterator, err = re_gmatch(res.body, [[(\d+)]], "jmo")
    if not iterator then
        core.log.error("failed to re.gmatch Nginx status: ", err)
        return
    end

    core.table.clear(ngx_status)
    for _, name in ipairs(ngx_statu_items) do
        local val = iterator()
        if not val then
            break
        end

        ngx_status[name] = val[0]
    end

    -- 存储状态
    local res, err = core.etcd.set("/node_status/" .. apisix_id, ngx_status)
    if not res then
        core.log.error("failed to create etcd client: ", err)
        return
    end

    if res.status >= 300 then
        core.log.error("failed to update node status, code: ", res.status,
                       " body: ", core.json.encode(res.body, true))
        return
    end
end


function _M.api()
    return {
        {
            methods = {"GET"},
            uri = "/apisix/status",
            handler = collect,
        }
    }
end


    local timer
function _M.init()
    -- 只要有一个work启动即可
    if timer or ngx.worker.id() ~= 0 then
        return
    end
    timer = core.timer.new(plugin_name, run_loop, {check_interval = 5 * 60})
end


return _M
