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

local base64_encode = require("base64").encode
local dkjson = require("dkjson")
local constants = require("apisix.constants")
local util = require("apisix.cli.util")
local file = require("apisix.cli.file")
local http = require("socket.http")
local https = require("ssl.https")
local ltn12 = require("ltn12")

local type = type
local ipairs = ipairs
local pairs = pairs
local print = print
local tonumber = tonumber
local str_format = string.format
local str_sub = string.sub
local table_concat = table.concat
local table_insert = table.insert
local io_stderr = io.stderr

local _M = {}

-- Timeout for all I/O operations
http.TIMEOUT = 3

local function parse_semantic_version(ver)
    local errmsg = "invalid semantic version: " .. ver

    local parts = util.split(ver, "-")
    if #parts > 2 then
        return nil, errmsg
    end

    if #parts == 2 then
        ver = parts[1]
    end

    local fields = util.split(ver, ".")
    if #fields ~= 3 then
        return nil, errmsg
    end

    local major = tonumber(fields[1])
    local minor = tonumber(fields[2])
    local patch = tonumber(fields[3])

    if not (major and minor and patch) then
        return nil, errmsg
    end

    return {
        major = major,
        minor = minor,
        patch = patch,
    }
end


local function compare_semantic_version(v1, v2)
    local ver1, err = parse_semantic_version(v1)
    if not ver1 then
        return nil, err
    end

    local ver2, err = parse_semantic_version(v2)
    if not ver2 then
        return nil, err
    end

    if ver1.major ~= ver2.major then
        return ver1.major < ver2.major
    end

    if ver1.minor ~= ver2.minor then
        return ver1.minor < ver2.minor
    end

    return ver1.patch < ver2.patch
end


local function request(url, yaml_conf)
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


local function get_etcd_token(user, password, host, yaml_conf)
    local auth_url = host .. "/v3/auth/authenticate"
    local json_auth = {
        name = user,
        password = password
    }

    local post_json_auth = dkjson.encode(json_auth)
    local response_body = {}

    local res, err
    local retry_time = 0
    while retry_time < 2 do
        res, err = request({
            url = auth_url,
            method = "POST",
            source = ltn12.source.string(post_json_auth),
            sink = ltn12.sink.table(response_body),
            headers = {
                ["Content-Length"] = #post_json_auth
            }
        }, yaml_conf)
        -- In case of failure, request returns nil followed by an error message.
        -- Else the first return value is just the number 1
        -- and followed by the response status code.
        if res then
            break
        end
        retry_time = retry_time + 1
        print(str_format("Warning! Request etcd endpoint \'%s\' error, %s, retry time=%s",
                            auth_url, err, retry_time))
    end

    local errmsg
    if not res then
        errmsg = str_format("request etcd endpoint \"%s\" error, %s\n", auth_url, err)
        return nil, errmsg
    end

    local res_auth = table_concat(response_body)
    local body_auth, _, err_auth = dkjson.decode(res_auth)
    if err_auth or (body_auth and not body_auth["token"]) then
        errmsg = str_format("got malformed auth message: \"%s\" from etcd \"%s\"\n",
                            res_auth, auth_url)
        return nil, errmsg
    end

    return body_auth.token
end


local function prepare_dirs_via_http(yaml_conf, args, index, host, host_count)
    local is_success = true

    local errmsg
    local auth_token
    local user = yaml_conf.etcd.user
    local password = yaml_conf.etcd.password
    if user and password then
        auth_token, errmsg = get_etcd_token(user, password, host, yaml_conf)
        if not auth_token then
            util.die(errmsg)
        end
    end


    local dirs = {}
    for name in pairs(constants.HTTP_ETCD_DIRECTORY) do
        dirs[name] = true
    end
    for name in pairs(constants.STREAM_ETCD_DIRECTORY) do
        dirs[name] = true
    end

    for dir_name in pairs(dirs) do
        local key =  (yaml_conf.etcd.prefix or "") .. dir_name .. "/"

        local put_url = host .. "/v3/kv/put"
        local post_json = '{"value":"' .. base64_encode("init_dir")
                            .. '", "key":"' .. base64_encode(key) .. '"}'
        local response_body = {}
        local headers = {["Content-Length"] = #post_json}
        if auth_token then
            headers["Authorization"] = auth_token
        end

        local res, err
        local retry_time = 0
        while retry_time < 2 do
            res, err = request({
                url = put_url,
                method = "POST",
                source = ltn12.source.string(post_json),
                sink = ltn12.sink.table(response_body),
                headers = headers
            }, yaml_conf)
            retry_time = retry_time + 1
            if res then
                break
            end
            print(str_format("Warning! Request etcd endpoint \'%s\' error, %s, retry time=%s",
                                put_url, err, retry_time))
        end

        if not res then
            errmsg = str_format("request etcd endpoint \"%s\" error, %s\n", put_url, err)
            util.die(errmsg)
        end

        local res_put = table_concat(response_body)
        if res_put:find("404 page not found", 1, true) then
            errmsg = str_format("gRPC gateway is not enabled in etcd cluster \"%s\",",
                                "which is required by Apache APISIX\n")
            util.die(errmsg)
        end

        if res_put:find("CommonName of client sending a request against gateway", 1, true) then
            errmsg = str_format("etcd \"client-cert-auth\" cannot be used with gRPC-gateway, "
                                .. "please configure the etcd username and password "
                                .. "in configuration file\n")
            util.die(errmsg)
        end

        if res_put:find("error", 1, true) then
            is_success = false
            if (index == host_count) then
                errmsg = str_format("got malformed key-put message: \"%s\" from etcd \"%s\"\n",
                                    res_put, put_url)
                util.die(errmsg)
            end

            break
        end

        if args and args["verbose"] then
            print(res_put)
        end
    end

    return is_success
end


local function prepare_dirs(yaml_conf, args, index, host, host_count)
    return prepare_dirs_via_http(yaml_conf, args, index, host, host_count)
end


local function etcd_request(url, method, body, headers, yaml_conf)
    local response_body = {}
    local req = {
        url = url,
        method = method,
        source = ltn12.source.string(body),
        sink = ltn12.sink.table(response_body),
        headers = headers
    }
    local _, code = request(req, yaml_conf)
    return table_concat(response_body), code
end

local function check_etcd_write_permission(yaml_conf)
    local etcd_conf = yaml_conf.etcd
    local headers = { ["Content-Type"] = "application/json" }
    local key = (etcd_conf.prefix or "") .. "/check_write_permission"
    local value = "test"
    local host = etcd_conf.host[1]

    local user = etcd_conf.user
    local password = etcd_conf.password
    if user and password then
        local token = get_etcd_token(user, password, host, yaml_conf)
        if token then
            headers["Authorization"] = token
        end
    end

    -- put
    local put_url = host .. "/v3/kv/put"
    local put_body = str_format('{"key":"%s","value":"%s"}',
        base64_encode(key),
        base64_encode(value))
    etcd_request(put_url, "POST", put_body, headers, yaml_conf)

    -- get
    local get_url = host .. "/v3/kv/range"
    local get_body = str_format('{"key":"%s"}', base64_encode(key))
    local get_res_body, get_code = etcd_request(get_url, "POST", get_body, headers, yaml_conf)

    if get_code == 200 then
        -- check if the key is set
        if get_res_body:find("kvs", 1, true) then
            -- delete
            local delete_url = host .. "/v3/kv/deleterange"
            local delete_body = str_format('{"key":"%s"}', base64_encode(key))
            etcd_request(delete_url, "POST", delete_body, headers, yaml_conf)
            return true
        end
    end
end


function _M.init(env, args)
    -- read_yaml_conf
    local yaml_conf, err = file.read_yaml_conf(env.apisix_home)
    if not yaml_conf then
        util.die("failed to read local yaml config of apisix: ", err)
    end

    if not yaml_conf.apisix then
        util.die("failed to read `apisix` field from yaml file when init etcd")
    end

    if yaml_conf.deployment.config_provider ~= "etcd" then
        return true
    end

    if not yaml_conf.etcd then
        util.die("failed to read `etcd` field from yaml file when init etcd")
    end

    -- convert old single etcd config to multiple etcd config
    if type(yaml_conf.etcd.host) == "string" then
        yaml_conf.etcd.host = {yaml_conf.etcd.host}
    end

    local host_count = #(yaml_conf.etcd.host)
    local scheme
    for i = 1, host_count do
        local host = yaml_conf.etcd.host[i]
        local fields = util.split(host, "://")
        if not fields then
            util.die("malformed etcd endpoint: ", host, "\n")
        end

        if not scheme then
            scheme = fields[1]
        elseif scheme ~= fields[1] then
            print([[WARNING: mixed protocols among etcd endpoints]])
        end
    end

    -- check the etcd cluster version
    local etcd_healthy_hosts = {}
    for index, host in ipairs(yaml_conf.etcd.host) do
        local version_url = host .. "/version"
        local errmsg

        local res, err
        local retry_time = 0

        local etcd = yaml_conf.etcd
        local max_retry = tonumber(etcd.startup_retry) or 2
        while retry_time < max_retry do
            res, err = request(version_url, yaml_conf)
            -- In case of failure, request returns nil followed by an error message.
            -- Else the first return value is the response body
            -- and followed by the response status code.
            if res then
                break
            end
            retry_time = retry_time + 1
            print(str_format("Warning! Request etcd endpoint \'%s\' error, %s, retry time=%s",
                             version_url, err, retry_time))
        end

        if res then
            local body, _, err = dkjson.decode(res)
            if err or (body and not body["etcdcluster"]) then
                errmsg = str_format("got malformed version message: \"%s\" from etcd \"%s\"\n", res,
                        version_url)
                util.die(errmsg)
            end

            local cluster_version = body["etcdcluster"]
            if compare_semantic_version(cluster_version, env.min_etcd_version) then
                util.die("etcd cluster version ", cluster_version,
                         " is less than the required version ", env.min_etcd_version,
                         ", please upgrade your etcd cluster\n")
            end

            table_insert(etcd_healthy_hosts, host)
        else
            io_stderr:write(str_format("request etcd endpoint \'%s\' error, %s\n", version_url,
                    err))
        end
    end

    if #etcd_healthy_hosts <= 0 then
        util.die("all etcd nodes are unavailable\n")
    end

    if (#etcd_healthy_hosts / host_count * 100) <= 50 then
        util.die("the etcd cluster needs at least 50% and above healthy nodes\n")
    end

    local etcd_ok = false
    for index, host in ipairs(etcd_healthy_hosts) do
        if prepare_dirs(yaml_conf, args, index, host, host_count) then
            etcd_ok = true
            break
        end
    end

    if not etcd_ok then
        util.die("none of the configured etcd works well\n")
    end
end

_M.check_etcd_write_permission = check_etcd_write_permission

return _M
