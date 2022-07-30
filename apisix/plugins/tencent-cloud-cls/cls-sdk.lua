-- https://cloud.tencent.com/document/api/614/16873
local pb = require "pb"
assert(pb.loadfile("apisix/plugins/tencent-cloud-cls/cls.pb"))
local http = require("resty.http")
local socket = require("socket")
local str_util = require("resty.string")
local core = require("apisix.core")
local json = core.json
local json_encode = json.encode

local ngx = ngx
local ngx_time = ngx.time
local ngx_now = ngx.now
local ngx_sha1_bin = ngx.sha1_bin
local ngx_hmac_sha1 = ngx.hmac_sha1

local fmt = string.format
local concat_tab = table.concat
local clear_tab = table.clear
local new_tab = table.new
local insert_tab = table.insert

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
    local ListTab = {}
    for _, v in ipairs(resolved.ip) do
        table.insert(ListTab, v)
    end
    return ListTab
end

local host_ip = tostring(unpack(get_ip(socket.dns.gethostname())))
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
    local http_request_info = fmt("%s\n%s\n%s\n%s\n", method, cls_api_path, format_params, format_headers)
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

local function send_cls_request(host, topic, secret_id, secret_key, pb_data)
    local http_new = http:new()
    http_new:set_timeouts(cls_conn_timeout, cls_send_timeout, cls_read_timeout)

    clear_tab(headers_cache)
    headers_cache["Host"] = host
    headers_cache["Content-Type"] = "application/x-protobuf"
    headers_cache["Authorization"] = sign(secret_id, secret_key, cls_api_path)

    -- TODO: support lz4/zstd compress
    params_cache.method = "POST"
    params_cache.body = pb_data

    local cls_url = "http://" .. host .. cls_api_path .. "?topic_id=" .. topic
    core.log.debug("CLS request URL: ", cls_url)

    local res, err = http_new:request_uri(cls_url, params_cache)
    if not res then
        return false, err
    end

    if res.status ~= 200 then
        err = fmt("got wrong status: %s, headers: %s, body, %s", res.status, json.encode(res.headers), res.body)
        -- 413, 404, 401, 403 are not retryable
        if res.status == 413 or res.status == 404 or res.status == 401 or res.status == 403 then
            core.log.err(err, ", not retryable")
            return true
        end

        return false, err
    end

    core.log.debug("CLS report success")
    return true
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

local function send_to_cls(secret_id, secret_key, host, topic_id, logs)
    clear_tab(log_group_list)
    local now = ngx_now() * 1000

    local total_size = 0
    local format_logs = new_tab(#logs, 0)
    -- sums of all value in a LogGroup should be no more than 5MB
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
            format_logs = new_tab(#logs - i, 0)
            total_size = 0
            local data = assert(pb.encode("cls.LogGroupList", log_group_list_pb))
            send_cls_request(host, topic_id, secret_id, secret_key, data)
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
    local data = assert(pb.encode("cls.LogGroupList", log_group_list_pb))
    return send_cls_request(host, topic_id, secret_id, secret_key, data)
end

return {
    send_to_cls = send_to_cls
}
