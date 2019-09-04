-- Copyright (C) Yuansheng Wang

local config_local = require("apisix.core.config_local")
local log          = require("apisix.core.log")
local json         = require("apisix.core.json")
local etcd         = require("resty.etcd")
local new_tab      = require("table.new")
local clone_tab    = require("table.clone")
local check_schema = require("apisix.core.schema").check
local exiting      = ngx.worker.exiting
local insert_tab   = table.insert
local type         = type
local ipairs       = ipairs
local setmetatable = setmetatable
local ngx_sleep    = ngx.sleep
local ngx_timer_at = ngx.timer.at
local ngx_time     = ngx.time
local sub_str      = string.sub
local tostring     = tostring
local tonumber     = tonumber
local pcall        = pcall


local _M = {
    version = 0.2,
    local_conf = config_local.local_conf,
    clear_local_cache = config_local.clear_cache,
}

local mt = {
    __index = _M,
    __tostring = function(self)
        return " etcd key: " .. self.key
    end
}

local function readdir(etcd_cli, key)
    if not etcd_cli then
        return nil, nil, "not inited"
    end

    local data, err = etcd_cli:readdir(key, true)
    if not data then
        -- log.error("failed to get key from etcd: ", err)
        return nil, nil, err
    end

    local body = data.body

    if type(body) ~= "table" then
        return nil, nil, "failed to read etcd dir"
    end

    if body.message then
        return nil, nil, body.message
    end

    return body.node, data.headers
end

--[[
    监听某个key 变动
--]]
local function waitdir(etcd_cli, key, modified_index)
    if not etcd_cli then
        return nil, nil, "not inited"
    end
    -- 监听 等待完成更新，并返回 类似于 set and read
    -- 详见 https://gitee.com/iresty/lua-resty-etcd#wait
    --
    local data, err = etcd_cli:waitdir(key, modified_index)
    if not data then
        -- log.error("failed to get key from etcd: ", err)
        return nil, nil, err
    end

    local body = data.body or {}

    if body.message then
        return nil, nil, body.message
    end

    return body.node, data.headers
end

--[[
    取短key
    例：
--]]
local function short_key(self, str)
    return sub_str(str, #self.key + 2)
end

--[[
    版本升级
--]]
function _M.upgrade_version(self, new_ver)
    new_ver = tonumber(new_ver)
    if not new_ver then
        return
    end

    local pre_index = self.prev_index
    if not pre_index then
        self.prev_index = new_ver
        return
    end

    -- 如果新版本号比当前版本号不大,退出
    if new_ver <= pre_index then
        return
    end

    -- 要求当前的版本号同步成新的版本号
    self.prev_index = new_ver
    return
end

--[[
    同步配置数据
--]]
local function sync_data(self)
    if not self.key then
        return nil, "missing 'key' arguments"
    end

    -- 初始化同步
    if self.values == nil then
        -- 根据key读取到对应的配置数据
        local dir_res, headers, err = readdir(self.etcd_cli, self.key)
        log.debug("readdir key: ", self.key, " res: ",
                  json.delay_encode(dir_res))
        if not dir_res then
            return false, err
        end

        if not dir_res.dir then
            return false, self.key .. " is not a dir"
        end

        if not dir_res.nodes then
            dir_res.nodes = {}
        end

        -- table.new(narray, nhash) 两个参数分别代表table里是array还是hash的，预分配
        -- self.values 是一个固定长度的table
        -- self.values_hash 是一个固定长度的hash table
        self.values = new_tab(#dir_res.nodes, 0)
        self.values_hash = new_tab(0, #dir_res.nodes)

        -- 标记当前配置数据是否发生改变
        local changed = false
        for _, item in ipairs(dir_res.nodes) do
            local key = short_key(self, item.key)
            -- 标记配置数据是否有效
            local data_valid = true
            if type(item.value) ~= "table" then
                data_valid = false
                log.error("invalid item data of [", self.key .. "/" .. key,
                          "], val: ", tostring(item.value),
                          ", it shoud be a object")
            end

            -- 配置数据进行schema 校验
            if data_valid and self.item_schema then
                data_valid, err = check_schema(self.item_schema, item.value)
                if not data_valid then
                    log.error("failed to check item data of [", self.key,
                              "] err:", err, " ,val: ", json.encode(item.value))
                end
            end

            -- 数据有效更新配置数据
            if data_valid then
                changed = true
                insert_tab(self.values, item)
                -- hash存的是values表里的index序号
                self.values_hash[key] = #self.values
                item.value.id = key
                item.clean_handlers = {}
            end
            -- 更新当前item里面的修改版本
            self:upgrade_version(item.modifiedIndex)
        end  --end do

        if headers then
            self:upgrade_version(headers["X-Etcd-Index"])
        end

        -- 修改当前的配置类别的版本号
        if changed then
            self.conf_version = self.conf_version + 1
        end
        -- 返回
        return true
    end --end if

    -- 如果self.values不为空，则需要监听变化
    -- 等待后续版本的数据
    local res, headers, err = waitdir(self.etcd_cli, self.key,
                                      self.prev_index + 1)
    log.debug("waitdir key: ", self.key, " prev_index: ", self.prev_index + 1)
    log.debug("res: ", json.delay_encode(res, true))
    log.debug("headers: ", json.delay_encode(headers, true))
    if not res then
        -- 没有变化
        return false, err
    end

    local key = short_key(self, res.key)
    -- 再次进行数据类型校验
    if res.value and type(res.value) ~= "table" then
        self:upgrade_version(res.modifiedIndex)
        return false, "invalid item data of [" .. self.key .. "/" .. key
                      .. "], val: " .. tostring(res.value)
                      .. ", it shoud be a object"
    end

    -- 再次进行数据 schema 校验
    if res.value and self.item_schema then
        local ok, err = check_schema(self.item_schema, res.value)
        if not ok then
            self:upgrade_version(res.modifiedIndex)

            return false, "failed to check item data of ["
                          .. self.key .. "] err:" .. err
        end
    end

    -- 用 etcd 里的版本更新 pre_index
    self:upgrade_version(res.modifiedIndex)

    if res.dir then
        if res.value then
            return false, "todo: support for parsing `dir` response "
                          .. "structures. " .. json.encode(res)
        end
        return false
    end

    --取出当前的value索引号
    local pre_index = self.values_hash[key]
    if pre_index then
        -- 取出当前的索引数据
        local pre_val = self.values[pre_index]
        if pre_val and pre_val.clean_handlers then
            for _, clean_handler in ipairs(pre_val.clean_handlers) do
                -- clean_handler ??? 执行的意义是什么?
                clean_handler(pre_val)
            end
            pre_val.clean_handlers = nil
        end

        if res.value then
            res.value.id = key
            self.values[pre_index] = res
            res.clean_handlers = {}

        else
            self.sync_times = self.sync_times + 1
            self.values[pre_index] = false  --删除了
        end

    elseif res.value then
        -- 新增插入的vlaues table中去
        insert_tab(self.values, res)
        self.values_hash[key] = #self.values
        res.value.id = key
    end

    -- avoid space waste
    -- todo: need to cover this path, it is important.
    if self.sync_times > 100 then
        -- 重置hash
        local count = 0
        for i = 1, #self.values do
            local val = self.values[i]
            self.values[i] = nil
            if val then
                count = count + 1
                self.values[count] = val
            end
        end

        for i = 1, count do
            key = short_key(self, self.values[i].key)
            self.values_hash[key] = i
        end
    end

    -- 更新配置版本
    self.conf_version = self.conf_version + 1
    return self.values
end


function _M.get(self, key)
    if not self.values_hash then
        return
    end

    local arr_idx = self.values_hash[tostring(key)]
    if not arr_idx then
        return nil
    end

    return self.values[arr_idx]
end

--[[
    功能： 自动提取配置
    @premature  回调第一个参数 premature，则是用于标识触发该回调的原因是否由于 timer 的到期。
                Nginx worker 的退出，也会触发当前所有有效的 timer。 这时候 premature 会被设置为 true。
                详见 https://github.com/openresty/lua-nginx-module#ngxtimerat
    @self  当前
--]]
local function _automatic_fetch(premature, self)
    if premature then
        return
    end

    local i = 0
    -- 如果工作线程不存在 并且 当前正在运行
    while not exiting() and self.running and i <= 32 do
        i = i + 1
        -- 调用同步数据的方法
        local ok, ok2, err = pcall(sync_data, self)
        if not ok then
            err = ok2
            log.error("failed to fetch data from etcd: ", err, ", ",
                      tostring(self))
            ngx_sleep(3)
            break

        elseif not ok2 and err then
            if err ~= "timeout" and err ~= "Key not found"
               and self.last_err ~= err then
                log.error("failed to fetch data from etcd: ", err, ", ",
                          tostring(self))
            end

            if err ~= self.last_err then
                self.last_err = err
                self.last_err_time = ngx_time()
            else
                if ngx_time() - self.last_err_time >= 30 then
                    self.last_err = nil
                end
            end
            ngx_sleep(0.5)

        elseif not ok2 then
            ngx_sleep(0.05)
        end
    end

    if not exiting() and self.running then
        ngx_timer_at(0, _automatic_fetch, self)
    end
end


function _M.new(key, opts)
    local local_conf, err = config_local.local_conf()
    if not local_conf then
        return nil, err
    end

    local etcd_conf = clone_tab(local_conf.etcd)
    local prefix = etcd_conf.prefix
    etcd_conf.prefix = nil
    -- 构建的 etcd 客户端
    local etcd_cli
    etcd_cli, err = etcd.new(etcd_conf)
    if not etcd_cli then
        return nil, err
    end

    -- 是否自动同步
    local automatic = opts and opts.automatic
    -- 指定的配置项json schema
    local item_schema = opts and opts.item_schema

    local obj = setmetatable({
        etcd_cli = etcd_cli,   --客户端
        key = key and prefix .. key,     --key
        automatic = automatic,   --自动同步开关
        item_schema = item_schema,  --配置项 schema
        sync_times = 0,        --同步次数
        running = true,   --是否正在运行
        conf_version = 0,  --配置对应的版本号
        values = nil,  --配置项目数据
        routes_hash = nil, --配置项目数据的hash存储--存储的是key：values里的索引号
        prev_index = nil, --etcd里的版本号
        last_err = nil,
        last_err_time = nil,
    }, mt)

    if automatic then
        if not key then
            return nil, "missing `key` argument"
        end
        --开始 ngx_timer 进行定时同步
        ngx_timer_at(0, _automatic_fetch, obj)
    end

    return obj
end


function _M.close(self)
    self.running = false
end


local function read_etcd_version(etcd_cli)
    if not etcd_cli then
        return nil, "not inited"
    end

    local data, err = etcd_cli:version()
    if not data then
        return nil, err
    end

    local body = data.body
    if type(body) ~= "table" then
        return nil, "failed to read response body when try to fetch etcd "
                    .. "version"
    end

    return body
end

function _M.server_version(self)
    if not self.running then
        return nil, "stoped"
    end

    return read_etcd_version(self.etcd_cli)
end


return _M
