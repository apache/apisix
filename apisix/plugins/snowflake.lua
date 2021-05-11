local ngx           = ngx
local core          = require("apisix.core")
local snowflake     = require("snowflake")
local uuid          = require('resty.jit-uuid')
local process       = require("ngx.process")
local tostring      = tostring
local math_ceil     = math.ceil


local worker_number = nil
local snowflake_init = nil
local plugin_name   = "snowflake"


local schema = {
    type = "object",
    properties = {
        header_name = {type = "string", default = "X-Request-Id"},
        include_in_response = {type = "boolean", default = true}
    }
}


local _M = {
    version = 0.1,
    priority = 11010,
    name = plugin_name,
    schema = schema,
}


function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end


local function gen_worker_number()
    if worker_number == nil then
        -- snowflake_init = nil
        local etcd_cli, prefix = core.etcd.new()
        local res, err = etcd_cli:grant(30)
        local data, err = etcd_cli:keepalive(res.body.ID)

        local prefix = prefix .. "/plugins/snowflake/"
        local uuid = uuid.generate_v4()
        local id = 1
        while( id < 1024 )
        do
            local res1, err1 = etcd_cli:setnx(prefix .. tostring(id), uuid)
            local res2, err2 = etcd_cli:get(prefix .. tostring(id))

            if err1 or err2 or res2.body.kvs[1].value ~= uuid then
                core.log.notice("worker_number " .. id .. " is not available")
                id = id + 1
                
            else
                worker_number = id

                local res3, err3 = etcd_cli:set(prefix .. tostring(id), uuid, {prev_kv = true, lease = res.body.ID})
                local handler = function(premature, etcd_cli, lease_id)
                    local data4, err4 = etcd_cli:keepalive(lease_id)
                    core.log.info("snowflake worker_number lease success.")
                end
                ngx.timer.every(10, handler, etcd_cli, res.body.ID)

                core.log.notice("snowflake worker_number: " .. id)
                break
            end
        end
        if worker_number  == nil then
            core.log.error("No worker_number is not available")
        end
    end
    return worker_number
end


local function next_id()
    if snowflake_init == nil then
        worker_number = gen_worker_number()
        local worker_id = worker_number % 32
        local datacenter_id = math_ceil(worker_number / 32)
        core.log.info("snowflake init datacenter_id: " ..  datacenter_id.. " worker_id: " .. worker_id)
        snowflake.init(worker_id, datacenter_id)
        snowflake_init = true
    end
    return snowflake:next_id()
end


function _M.rewrite(conf, ctx)
    local headers = ngx.req.get_headers()
    local uuid_val = next_id()
    if not headers[conf.header_name] then
        core.request.set_header(ctx, conf.header_name, uuid_val)
    end

    if conf.include_in_response then
        ctx.x_request_id = uuid_val
    end
end


function _M.header_filter(conf, ctx)
    if not conf.include_in_response then
        return
    end

    local headers = ngx.resp.get_headers()
    if not headers[conf.header_name] then
        core.response.set_header(conf.header_name, ctx.x_request_id)
    end
end


function _M.init()
    if process.type() == "worker" then
        ngx.timer.at(0, next_id)
    end
end


function _M.api()
    return {
        {
            methods = {"GET"},
            uri = "/apisix/plugin/snowflake",
            handler = next_id,
        },
    }
end


return _M