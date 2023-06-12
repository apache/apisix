--
-- Licensed to the Apache Software Foundation (ASF) under one or more
-- contributor license agreements.  See the NOTICE file distributed with
-- this work for additional information regarding copyright ownership.
-- The ASF licenses this file to You under the Apache License, Version 2.0
-- (the "License"); you may not use this file except in compliance with
-- the License.  You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--

local pb = require "pb"
local protoc = require("protoc").new()
local http = require("resty.http")
local socket = require("socket")
local str_util = require("resty.string")
local core = require("apisix.core")
local core_gethostname = require("apisix.core.utils").gethostname
local json = core.json
local json_encode = json.encode
local ngx = ngx
local ngx_time = ngx.time
local ngx_now = ngx.now
local ngx_sha1_bin = ngx.sha1_bin
local ngx_hmac_sha1 = ngx.hmac_sha1
local fmt = string.format
local table = table
local concat_tab = table.concat
local clear_tab = table.clear
local new_tab = table.new
local insert_tab = table.insert
local ipairs = ipairs
local pairs = pairs
local type = type
local tostring = tostring
local setmetatable = setmetatable
local pcall = pcall

-- api doc https://www.tencentcloud.com/document/product/614/16873
local MAX_SINGLE_VALUE_SIZE = 1 * 1024 * 1024
local MAX_LOG_GROUP_VALUE_SIZE = 5 * 1024 * 1024 -- 5MB

local cls_api_path = "/structuredlog"
local auth_expire_time = 60
local cls_conn_timeout = 1000
local cls_read_timeout = 10000
local cls_send_timeout = 10000

local headers_cache = {}
local params_cache = {
    ssl_verify = false,
    headers = headers_cache,
}


local function get_ip(hostname)
    local _, resolved = socket.dns.toip(hostname)
    local ip_list = {}
    for _, v in ipairs(resolved.ip) do
        insert_tab(ip_list, v)
    end
    return ip_list
end

local host_ip = tostring(unpack(get_ip(core_gethostname())))
local log_group_list = {}
local log_group_list_pb = {
    logGroupList = log_group_list,
}


local function sha1(msg)
    return str_util.to_hex(ngx_sha1_bin(msg))
end


local function sha1_hmac(key, msg)
    return str_util.to_hex(ngx_hmac_sha1(key, msg))
end


-- sign algorithm https://cloud.tencent.com/document/product/614/12445
local function sign(secret_id, secret_key)
    local method = "post"
    local format_params = ""
    local format_headers = ""
    local sign_algorithm = "sha1"
    local http_request_info = fmt("%s\n%s\n%s\n%s\n",
                                  method, cls_api_path, format_params, format_headers)
    local cur_time = ngx_time()
    local sign_time = fmt("%d;%d", cur_time, cur_time + auth_expire_time)
    local string_to_sign = fmt("%s\n%s\n%s\n", sign_algorithm, sign_time, sha1(http_request_info))

    local sign_key = sha1_hmac(secret_key, sign_time)
    local signature = sha1_hmac(sign_key, string_to_sign)

    local arr = {
        "q-sign-algorithm=sha1",
        "q-ak=" .. secret_id,
        "q-sign-time=" .. sign_time,
        "q-key-time=" .. sign_time,
        "q-header-list=",
        "q-url-param-list=",
        "q-signature=" .. signature,
    }

    return concat_tab(arr, '&')
end


-- normalized log data for CLS API
local function normalize_log(log)
    local normalized_log = {}
    local log_size = 4 -- empty obj alignment
    for k, v in pairs(log) do
        local v_type = type(v)
        local field = { key = k, value = "" }
        if v_type == "string" then
            field["value"] = v
        elseif v_type == "number" then
            field["value"] = tostring(v)
        elseif v_type == "table" then
            field["value"] = json_encode(v)
        else
            field["value"] = tostring(v)
            core.log.warn("unexpected type " .. v_type .. " for field " .. k)
        end
        if #field.value > MAX_SINGLE_VALUE_SIZE then
            core.log.warn(field.key, " value size over ", MAX_SINGLE_VALUE_SIZE, " , truncated")
            field.value = field.value:sub(1, MAX_SINGLE_VALUE_SIZE)
        end
        insert_tab(normalized_log, field)
        log_size = log_size + #field.key + #field.value
    end
    return normalized_log, log_size
end


local _M = { version = 0.1 }
local mt = { __index = _M }

local pb_state
local function init_pb_state()
    local old_pb_state = pb.state(nil)
    protoc.reload()
    local cls_sdk_protoc = protoc.new()
    -- proto file in https://www.tencentcloud.com/document/product/614/42787
    local ok, err = pcall(cls_sdk_protoc.load, cls_sdk_protoc, [[
package cls;

message Log
{
  message Content
  {
    required string key   = 1; // Key of each field group
    required string value = 2; // Value of each field group
  }
  required int64   time     = 1; // Unix timestamp
  repeated Content contents = 2; // Multiple key-value pairs in one log
}

message LogTag
{
  required string key       = 1;
  required string value     = 2;
}

message LogGroup
{
  repeated Log    logs        = 1; // Log array consisting of multiple logs
  optional string contextFlow = 2; // This parameter does not take effect currently
  optional string filename    = 3; // Log filename
  optional string source      = 4; // Log source, which is generally the machine IP
  repeated LogTag logTags     = 5;
}

message LogGroupList
{
  repeated LogGroup logGroupList = 1; // Log group list
}
        ]], "tencent-cloud-cls/cls.proto")
    if not ok then
        cls_sdk_protoc:reset()
        pb.state(old_pb_state)
        return "failed to load cls.proto: ".. err
    end
    pb_state = pb.state(old_pb_state)
end


function _M.new(host, topic, secret_id, secret_key)
    if not pb_state then
        local err = init_pb_state()
        if err then
            return nil, err
        end
    end
    local self = {
        host = host,
        topic = topic,
        secret_id = secret_id,
        secret_key = secret_key,
    }
    return setmetatable(self, mt)
end


local function do_request_uri(uri, params)
    local client = http:new()
    client:set_timeouts(cls_conn_timeout, cls_send_timeout, cls_read_timeout)
    local res, err = client:request_uri(uri, params)
    client:close()
    return res, err
end


function _M.send_cls_request(self, pb_obj)
    -- recovery of stored pb_store
    local old_pb_state = pb.state(pb_state)
    local ok, pb_data = pcall(pb.encode, "cls.LogGroupList", pb_obj)
    pb_state = pb.state(old_pb_state)
    if not ok or not pb_data then
        core.log.error("failed to encode LogGroupList, err: ", pb_data)
        return false, pb_data
    end

    clear_tab(headers_cache)
    headers_cache["Host"] = self.host
    headers_cache["Content-Type"] = "application/x-protobuf"
    headers_cache["Authorization"] = sign(self.secret_id, self.secret_key, cls_api_path)

    -- TODO: support lz4/zstd compress
    params_cache.method = "POST"
    params_cache.body = pb_data

    local cls_url = "http://" .. self.host .. cls_api_path .. "?topic_id=" .. self.topic
    core.log.debug("CLS request URL: ", cls_url)

    local res, err = do_request_uri(cls_url, params_cache)
    if not res then
        return false, err
    end

    if res.status ~= 200 then
        err = fmt("got wrong status: %s, headers: %s, body, %s",
                res.status, json.encode(res.headers), res.body)
        -- 413, 404, 401, 403 are not retryable
        if res.status == 413 or res.status == 404 or res.status == 401 or res.status == 403 then
            core.log.error(err, ", not retryable")
            return true
        end

        return false, err
    end

    core.log.debug("CLS report success")
    return true
end


function _M.send_to_cls(self, logs)
    clear_tab(log_group_list)
    local now = ngx_now() * 1000

    local total_size = 0
    local format_logs = new_tab(#logs, 0)
    -- sums of all value in all LogGroup should be no more than 5MB
    -- so send whenever size exceed max size
    local group_list_start = 1
    for i = 1, #logs, 1 do
        local contents, log_size = normalize_log(logs[i])
        if log_size > MAX_LOG_GROUP_VALUE_SIZE then
            core.log.error("size of log is over 5MB, dropped")
            goto continue
        end
        total_size = total_size + log_size
        if total_size > MAX_LOG_GROUP_VALUE_SIZE then
            insert_tab(log_group_list, {
                logs = format_logs,
                source = host_ip,
            })
            local ok, err = self:send_cls_request(log_group_list_pb)
            if not ok then
                return false, err, group_list_start
            end
            group_list_start = i
            format_logs = new_tab(#logs - i, 0)
            total_size = 0
            clear_tab(log_group_list)
        end
        insert_tab(format_logs, {
            time = now,
            contents = contents,
        })
        :: continue ::
    end

    insert_tab(log_group_list, {
        logs = format_logs,
        source = host_ip,
    })
    local ok, err = self:send_cls_request(log_group_list_pb)
    return ok, err, group_list_start
end

return _M
