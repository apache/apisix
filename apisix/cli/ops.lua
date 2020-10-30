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

local env = require("apisix.cli.env")
local etcd = require("apisix.cli.etcd")
local file = require("apisix.cli.file")
local util = require("apisix.cli.util")
local ngx_tpl = require("apisix.cli.ngx_tpl")
local template = require("resty.template")

local type = type
local pairs = pairs
local print = print
local ipairs = ipairs
local tonumber = tonumber
local tostring = tostring
local str_find = string.find
local str_sub = string.sub
local max = math.max
local floor = math.floor
local popen = io.popen
local execute = os.execute
local getenv = os.getenv
local error = error
local stderr = io.stderr

local openresty_args = [[openresty  -p ]] .. env.apisix_home .. [[ -c ]]
                       .. env.apisix_home .. [[/conf/nginx.conf]]

local _M = {}


local function get_openresty_version()
    local str = "nginx version: openresty/"
    local ret = util.execute_cmd("openresty -v 2>&1")
    local pos = str_find(ret, str, 1, true)
    if pos then
        return str_sub(ret, pos + #str)
    end

    str = "nginx version: nginx/"
    ret = util.execute_cmd("openresty -v 2>&1")
    pos = str_find(ret, str, 1, true)
    if pos then
        return str_sub(ret, pos + #str)
    end

    return nil
end


local function check_version(cur_ver_s, need_ver_s)
    local cur_vers = util.split(cur_ver_s, [[.]])
    local need_vers = util.split(need_ver_s, [[.]])
    local len = max(#cur_vers, #need_vers)

    for i = 1, len do
        local cur_ver = tonumber(cur_vers[i]) or 0
        local need_ver = tonumber(need_vers[i]) or 0
        if cur_ver > need_ver then
            return true
        end

        if cur_ver < need_ver then
            return false
        end
    end

    return true
end


function _M.init()
    if env.is_root_path then
        print("Warning! Running apisix under /root is only suitable for "
              .. "development environments and it is dangerous to do so."
              .. "It is recommended to run APISIX in a directory other than "
              .. "/root.")
    end

    -- read_yaml_conf
    local yaml_conf, err = file.read_yaml_conf()
    if not yaml_conf then
        error("failed to read local yaml config of apisix: " .. err)
    end

    -- check the Admin API token
    local checked_admin_key = false
    if yaml_conf.apisix.enable_admin and yaml_conf.apisix.allow_admin then
        for _, allow_ip in ipairs(yaml_conf.apisix.allow_admin) do
            if allow_ip == "127.0.0.0/24" then
                checked_admin_key = true
                break
            end
        end
    end

    if yaml_conf.apisix.enable_admin and not checked_admin_key then
        local help = [[

%s
Please modify "admin_key" in conf/config.yaml .

]]
        if type(yaml_conf.apisix.admin_key) ~= "table" or
           #yaml_conf.apisix.admin_key == 0
        then
            return util.die(help:format("ERROR: missing valid Admin API token."))
        end

        for _, admin in ipairs(yaml_conf.apisix.admin_key) do
            if type(admin.key) == "table" then
                admin.key = ""
            else
                admin.key = tostring(admin.key)
            end

            if admin.key == "" then
                return util.die(help:format("ERROR: missing valid Admin API token."),
                                "\n")
            end

            if admin.key == "edd1c9f034335f136f87ad84b625c8f1" then
                local msg = help:format([[WARNING: using fixed Admin API token has security risk.]])
                stderr:write(msg, "\n")
            end
        end
    end

    local with_module_status = true

    local or_ver = util.execute_cmd("openresty -V 2>&1")
    if or_ver and not or_ver:find("http_stub_status_module", 1, true) then
        stderr:write("'http_stub_status_module' module is missing in ",
                     "your openresty, please check it out. Without this ",
                     "module, there will be fewer monitoring indicators.\n")

        with_module_status = false
    end

    local enabled_plugins = {}
    for i, name in ipairs(yaml_conf.plugins) do
        enabled_plugins[name] = true
    end

    if enabled_plugins["proxy-cache"] and not yaml_conf.apisix.proxy_cache then
        error("missing apisix.proxy_cache for plugin proxy-cache")
    end

    --support multiple ports listen, compatible with the original style
    if type(yaml_conf.apisix.node_listen) == "number" then
        local node_listen = {yaml_conf.apisix.node_listen}
        yaml_conf.apisix.node_listen = node_listen
    end

    if type(yaml_conf.apisix.ssl.listen_port) == "number" then
        local listen_port = {yaml_conf.apisix.ssl.listen_port}
        yaml_conf.apisix.ssl.listen_port = listen_port
    end

    if yaml_conf.apisix.ssl.ssl_trusted_certificate ~= nil then
        local ok, err = file.is_file_exist(yaml_conf.apisix.ssl.ssl_trusted_certificate)
        if not ok then
            util.die(err, "\n")
        end
    end

    -- Using template.render
    local sys_conf = {
        lua_path           = env.pkg_path_org,
        lua_cpath          = env.pkg_cpath_org,
        apisix_lua_home    = env.apisix_home,
        os_name            = util.trim(util.execute_cmd("uname")),
        with_module_status = with_module_status,
        error_log          = { level = "warn" },
        enabled_plugins    = enabled_plugins,
    }

    if not yaml_conf.apisix then
        error("failed to read `apisix` field from yaml file")
    end

    if not yaml_conf.nginx_config then
        error("failed to read `nginx_config` field from yaml file")
    end

    if util.is_32bit_arch() then
        sys_conf["worker_rlimit_core"] = "4G"
    else
        sys_conf["worker_rlimit_core"] = "16G"
    end

    for k,v in pairs(yaml_conf.apisix) do
        sys_conf[k] = v
    end

    for k,v in pairs(yaml_conf.nginx_config) do
        sys_conf[k] = v
    end

    local wrn = sys_conf["worker_rlimit_nofile"]
    local wc = sys_conf["event"]["worker_connections"]
    if not wrn or wrn <= wc then
        -- ensure the number of fds is slightly larger than the number of conn
        sys_conf["worker_rlimit_nofile"] = wc + 128
    end

    if sys_conf["enable_dev_mode"] == true then
        sys_conf["worker_processes"] = 1
        sys_conf["enable_reuseport"] = false

    elseif tonumber(sys_conf["worker_processes"]) == nil then
        sys_conf["worker_processes"] = "auto"
    end

    if sys_conf.allow_admin and #sys_conf.allow_admin == 0 then
        sys_conf.allow_admin = nil
    end

    local dns_resolver = sys_conf["dns_resolver"]
    if not dns_resolver or #dns_resolver == 0 then
        local dns_addrs, err = util.local_dns_resolver("/etc/resolv.conf")
        if not dns_addrs then
            return util.die("failed to import local DNS: ", err)
        end

        if #dns_addrs == 0 then
            return util.die("local DNS is empty")
        end

        sys_conf["dns_resolver"] = dns_addrs
    end

    local env_worker_processes = getenv("APISIX_WORKER_PROCESSES")
    if env_worker_processes then
        sys_conf["worker_processes"] = floor(tonumber(env_worker_processes))
    end

    local conf_render = template.compile(ngx_tpl)
    local ngxconf = conf_render(sys_conf)

    local ok, err = file.write_file(env.apisix_home .. "/conf/nginx.conf",
                                    ngxconf)
    if not ok then
        return util.die("failed to update nginx.conf: ", err)
    end

    local op_ver = get_openresty_version()
    if op_ver == nil then
        return util.die("can not find openresty\n")
    end

    local need_ver = "1.15.8"
    if not check_version(op_ver, need_ver) then
        return util.die("openresty version must >=", need_ver, " current ", op_ver, "\n")
    end
end


function _M.start(...)
    local cmd_logs = "mkdir -p " .. env.apisix_home .. "/logs"
    execute(cmd_logs)

    -- check running
    local pid = file.read_file(env.pid_path)
    if pid then
        local hd = popen("lsof -p " .. pid)
        local res = hd:read("*a")
        if res and res ~= "" then
            print("APISIX is running...")
            return nil
        end
    end

    _M.init(...)
    etcd.init(...)

    execute(openresty_args)
end


function _M.stop()
    execute(openresty_args .. [[ -s stop]])
end


function _M.restart()
    _M.stop()
    _M.start()
end


function _M.reload()
    -- reinit nginx.conf
    _M.init()

    local test_cmd = openresty_args .. [[ -t -q ]]
    -- When success,
    -- On linux, os.execute returns 0,
    -- On macos, os.execute returns 3 values: true, exit, 0,
    -- and we need the first.
    local test_ret = execute(test_cmd)
    if test_ret == 0 or test_ret == true then
        local cmd = openresty_args .. [[ -s reload]]
        execute(cmd)
        return
    end

    util.die("test openresty failed")
end


return _M
