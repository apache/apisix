-- Copyright (C) Yuansheng Wang

local log = require("apisix.core.log")
local fetch_local_conf = require("apisix.core.config_local").local_conf
local encode_json = require("cjson.safe").encode
local etcd = require("resty.etcd")
local new_tab = require("table.new")
local exiting = ngx.worker.exiting
local insert_tab = table.insert
local type = type
local ipairs = ipairs
local setmetatable = setmetatable
local ngx_sleep = ngx.sleep
local ngx_timer_at = ngx.timer.at
local sub_str = string.sub


local _M = {
    version = 0.1,
    local_conf = fetch_local_conf,
}
local mt = {__index = _M}


local function readdir(etcd_cli, key)
    if not etcd_cli then
        return nil, "not inited"
    end

    local data, err = etcd_cli:readdir(key, true)
    if not data then
        -- log.error("failed to get key from etcd: ", err)
        return nil, err
    end

    local body = data.body

    if type(body) ~= "table" then
        return nil, "failed to read etcd dir"
    end

    if body.message then
        return nil, body.message
    end

    return body.node
end

local function waitdir(etcd_cli, key, modified_index)
    if not etcd_cli then
        return nil, "not inited"
    end

    local data, err = etcd_cli:waitdir(key, modified_index)
    if not data then
        -- log.error("failed to get key from etcd: ", err)
        return nil, err
    end

    local body = data.body or {}

    if body.message then
        return nil, body.message
    end

    return body.node
end


local function short_key(self, str)
    return sub_str(str, #self.key + 2)
end


function _M.fetch(self)
    if self.values == nil then
        local dir_res, err = readdir(self.etcd_cli, self.key)
        if not dir_res then
            return nil, err
        end

        if not dir_res.dir then
            return nil, self.key .. " is not a dir"
        end

        self.values = new_tab(#dir_res.nodes, 0)
        self.values_hash = new_tab(0, #dir_res.nodes)

        for _, item in ipairs(dir_res.nodes) do
            insert_tab(self.values, item)
            local key = short_key(self, item.key)
            self.values_hash[key] = #self.values

            if not self.prev_index or item.modifiedIndex > self.prev_index then
                self.prev_index = item.modifiedIndex
            end
        end

        return self.values
    end

    local res, err = waitdir(self.etcd_cli, self.key, self.prev_index + 1)
    if not res then
        return nil, err
    end

    if res.dir then
        log.error("todo: support for parsing `dir` response structures. ",
                  encode_json(res))
        return self.values
    end
    -- log.warn("waitdir: ", encode_json(res))

    if not self.prev_index or res.modifiedIndex > self.prev_index then
        self.prev_index = res.modifiedIndex
    end

    local key = short_key(self, res.key)
    local pre_index = self.values_hash[key]
    if pre_index then
        if res.value then
            self.values[pre_index] = res

        else
            self.sync_times = self.sync_times + 1
            self.values[pre_index] = false
        end

    elseif res.value then
        insert_tab(self.values, res)
        self.values_hash[key] = #self.values
    end

    -- avoid space waste
    -- todo: need to cover this path, it is important.
    if self.sync_times > 100 then
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

    self.version = self.version + 1
    return self.values
end


function _M.get(self, key)
    local arr_idx = self.values_hash[tostring(key)]
    if not arr_idx then
        return nil
    end

    return self.values[arr_idx]
end


local function _automatic_fetch(premature, self)
    if premature then
        return
    end

    while not exiting() and self.running do
        local ok, res, err = pcall(self.fetch, self)
        if not ok then
            err = res
            log.error("failed to fetch data from etcd: ", err)
            ngx_sleep(10)

        elseif not res and err ~= "timeout" then
            log.error("failed to fetch data from etcd: ", err)
            ngx_sleep(5)
        end
    end
end


function _M.new(key, opts)
    if not key then
        return nil, "missing `key` argument"
    end

    local local_conf, err = fetch_local_conf()
    if not local_conf then
        return nil, err
    end

    local etcd_cli
    etcd_cli, err = etcd.new(local_conf.etcd)
    if not etcd_cli then
        return nil, err
    end

    local automatic = opts and opts.automatic

    local obj = setmetatable({
        etcd_cli = etcd_cli,
        values = nil,
        routes_hash = nil,
        prev_index = nil,
        key = key,
        automatic = automatic,
        sync_times = 0,
        running = true,
        version = 0,
    }, mt)

    if automatic then
        ngx_timer_at(0, _automatic_fetch, obj)
    end

    return obj
end


function _M.close(self)
    self.running = false
end


return _M
