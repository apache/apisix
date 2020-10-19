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

local dkjson = require("dkjson")
local file = require("apisix.cli.file")
local util = require("apisix.cli.util")
local env = require("apisix.cli.env")

local base64_encode = require("base64").encode

local type = type
local ipairs = ipairs
local print = print
local tonumber = tonumber
local str_format = string.format

local _M = {}


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


function _M.init(show_output)
    -- read_yaml_conf
    local yaml_conf, err = file.read_yaml_conf()
    if not yaml_conf then
        return util.die("failed to read local yaml config of apisix: ",
                        err)
    end

    if not yaml_conf.apisix then
        return util.die("failed to read `apisix` field from yaml file ",
                        "while initializing etcd")
    end

    if yaml_conf.apisix.config_center ~= "etcd" then
        return true
    end

    if not yaml_conf.etcd then
        return util.die("failed to read `etcd` field from yaml file ",
                        "while initializing etcd")
    end

    --convert old single etcd config to multiple etcd config
    if type(yaml_conf.etcd.host) == "string" then
        yaml_conf.etcd.host = { yaml_conf.etcd.host }
    end

    local etcd_conf = yaml_conf.etcd
    local timeout = yaml_conf.etcd.timeout or 3
    local host_count = #(yaml_conf.etcd.host)
    local uri

    for _, host in ipairs(etcd_conf.host) do
        -- check the etcd cluster version
        uri = host .. "/version"
        local cmd = str_format("curl -s -m %d %s", timeout * 2, uri)
        local res = util.execute_cmd(cmd)
        local errmsg = str_format("got malformed version message: \"%s\" from etcd\n",
                                  res)

        local body, _, err = dkjson.decode(res)
        if err then
            return util.die(errmsg)
        end

        local cluster_version = body["etcdcluster"]
        if not cluster_version then
            return util.die(errmsg)
        end

        if compare_semantic_version(cluster_version, env.min_etcd_version) then
            return util.die("etcd cluster version ", cluster_version,
                            " is less than the required version ",
                            env.min_etcd_version,
                            ", please upgrade your etcd cluster\n")
        end
    end


    local etcd_ok = false
    for index, host in ipairs(etcd_conf.host) do
        local is_success = true

        for _, dir_name in ipairs({"/routes", "/upstreams", "/services",
                                   "/plugins", "/consumers", "/node_status",
                                   "/ssl", "/global_rules", "/stream_routes",
                                   "/proto"})
        do
            local key =  (etcd_conf.prefix or "") .. dir_name .. "/"

            local uri = host .. "/v3/kv/put"
            local post_json = '{"value":"' .. base64_encode("init_dir")
                              .. '", "key":"' .. base64_encode(key) .. '"}'

            local cmd = "curl " .. uri .. " -X POST -d '" .. post_json
                        .. "' --connect-timeout " .. timeout
                        .. " --max-time " .. timeout * 2 .. " --retry 1 2>&1"

            local res = util.execute_cmd(cmd)
            if res:find("error", 1, true) then
                is_success = false
                if index == host_count then
                    return util.die(cmd, "\n", res)
                end

                break
            end

            if show_output then
                print(cmd)
                print(res)
            end
        end

        if is_success then
            etcd_ok = true
            break
        end
    end

    if not etcd_ok then
        return util.die("none of the configured etcd works well")
    end
end


return _M
