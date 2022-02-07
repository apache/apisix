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
local ver = require("apisix.core.version")
local etcd = require("apisix.cli.etcd")
local util = require("apisix.cli.util")
local file = require("apisix.cli.file")
local schema = require("apisix.cli.schema")
local ngx_tpl = require("apisix.cli.ngx_tpl")
local profile = require("apisix.core.profile")
local template = require("resty.template")
local argparse = require("argparse")
local pl_path = require("pl.path")

local stderr = io.stderr
local ipairs = ipairs
local pairs = pairs
local print = print
local type = type
local tostring = tostring
local tonumber = tonumber
local io_open = io.open
local execute = os.execute
local os_rename = os.rename
local table_insert = table.insert
local getenv = os.getenv
local max = math.max
local floor = math.floor
local str_find = string.find
local str_byte = string.byte
local str_sub = string.sub
local str_format = string.format

local _M = {}


local function help()
    print([[
Usage: apisix [action] <argument>

help:       show this message, then exit
init:       initialize the local nginx.conf
init_etcd:  initialize the data of etcd
start:      start the apisix server
stop:       stop the apisix server
quit:       stop the apisix server gracefully
restart:    restart the apisix server
reload:     reload the apisix server
version:    print the version of apisix
]])
end


local function version_greater_equal(cur_ver_s, need_ver_s)
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


local function get_openresty_version()
    local str = "nginx version: openresty/"
    local ret = util.execute_cmd("openresty -v 2>&1")
    local pos = str_find(ret, str, 1, true)
    if pos then
        return str_sub(ret, pos + #str)
    end

    str = "nginx version: nginx/"
    pos = str_find(ret, str, 1, true)
    if pos then
        return str_sub(ret, pos + #str)
    end
end


local function local_dns_resolver(file_path)
    local file, err = io_open(file_path, "rb")
    if not file then
        return false, "failed to open file: " .. file_path .. ", error info:" .. err
    end

    local dns_addrs = {}
    for line in file:lines() do
        local addr, n = line:gsub("^nameserver%s+([^%s]+)%s*$", "%1")
        if n == 1 then
            table_insert(dns_addrs, addr)
        end
    end

    file:close()
    return dns_addrs
end
-- exported for test
_M.local_dns_resolver = local_dns_resolver


local function version()
    print(ver['VERSION'])
end


local function get_lua_path(conf)
    -- we use "" as the placeholder to enforce the type to be string
    if conf and conf ~= "" then
        if #conf < 2 then
            -- the shortest valid path is ';;'
            util.die("invalid extra_lua_path/extra_lua_cpath: \"", conf, "\"\n")
        end

        local path = conf
        if path:byte(-1) ~= str_byte(';') then
            path = path .. ';'
        end
        return path
    end

    return ""
end


local function init(env)
    if env.is_root_path then
        print('Warning! Running apisix under /root is only suitable for '
              .. 'development environments and it is dangerous to do so. '
              .. 'It is recommended to run APISIX in a directory '
              .. 'other than /root.')
    end

    local min_ulimit = 1024
    if env.ulimit <= min_ulimit then
        print(str_format("Warning! Current maximum number of open file "
                .. "descriptors [%d] is not greater than %d, please increase user limits by "
                .. "execute \'ulimit -n <new user limits>\' , otherwise the performance"
                .. " is low.", env.ulimit, min_ulimit))
    end

    -- read_yaml_conf
    local yaml_conf, err = file.read_yaml_conf(env.apisix_home)
    if not yaml_conf then
        util.die("failed to read local yaml config of apisix: ", err, "\n")
    end

    local ok, err = schema.validate(yaml_conf)
    if not ok then
        util.die(err, "\n")
    end

    -- check the Admin API token
    local checked_admin_key = false
    if yaml_conf.apisix.enable_admin and yaml_conf.apisix.allow_admin then
        for _, allow_ip in ipairs(yaml_conf.apisix.allow_admin) do
            if allow_ip == "127.0.0.0/24" then
                checked_admin_key = true
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
            util.die(help:format("ERROR: missing valid Admin API token."))
        end

        for _, admin in ipairs(yaml_conf.apisix.admin_key) do
            if type(admin.key) == "table" then
                admin.key = ""
            else
                admin.key = tostring(admin.key)
            end

            if admin.key == "" then
                util.die(help:format("ERROR: missing valid Admin API token."), "\n")
            end

            if admin.key == "edd1c9f034335f136f87ad84b625c8f1" then
                stderr:write(
                    help:format([[WARNING: using fixed Admin API token has security risk.]]),
                    "\n"
                )
            end
        end
    end

    if yaml_conf.apisix.enable_admin and
        yaml_conf.apisix.config_center == "yaml"
    then
        util.die("ERROR: Admin API can only be used with etcd config_center.\n")
    end

    local or_ver = get_openresty_version()
    if or_ver == nil then
        util.die("can not find openresty\n")
    end

    local need_ver = "1.17.8"
    if not version_greater_equal(or_ver, need_ver) then
        util.die("openresty version must >=", need_ver, " current ", or_ver, "\n")
    end

    local use_openresty_1_17 = false
    if not version_greater_equal(or_ver, "1.19.3") then
        use_openresty_1_17 = true
    end

    local or_info = util.execute_cmd("openresty -V 2>&1")
    local with_module_status = true
    if or_info and not or_info:find("http_stub_status_module", 1, true) then
        stderr:write("'http_stub_status_module' module is missing in ",
                     "your openresty, please check it out. Without this ",
                     "module, there will be fewer monitoring indicators.\n")
        with_module_status = false
    end

    local use_apisix_openresty = true
    if or_info and not or_info:find("apisix-nginx-module", 1, true) then
        use_apisix_openresty = false
    end

    local enabled_plugins = {}
    for i, name in ipairs(yaml_conf.plugins) do
        enabled_plugins[name] = true
    end

    if enabled_plugins["proxy-cache"] and not yaml_conf.apisix.proxy_cache then
        util.die("missing apisix.proxy_cache for plugin proxy-cache\n")
    end

    if enabled_plugins["batch-requests"] then
        local pass_real_client_ip = false
        local real_ip_from = yaml_conf.nginx_config.http.real_ip_from
        -- the real_ip_from is enabled by default, we just need to make sure it's
        -- not disabled by the users
        if real_ip_from then
            for _, ip in ipairs(real_ip_from) do
                -- TODO: handle cidr
                if ip == "127.0.0.1" or ip == "0.0.0.0/0" then
                    pass_real_client_ip = true
                end
            end
        end

        if not pass_real_client_ip then
            util.die("missing '127.0.0.1' in the nginx_config.http.real_ip_from for plugin " ..
                     "batch-requests\n")
        end
    end

    local ports_to_check = {}

    -- listen in admin use a separate port, support specific IP, compatible with the original style
    local admin_server_addr
    if yaml_conf.apisix.enable_admin then
        if yaml_conf.apisix.admin_listen or yaml_conf.apisix.port_admin then
            local ip = "0.0.0.0"
            local port = yaml_conf.apisix.port_admin or 9180

            if yaml_conf.apisix.admin_listen then
                ip = yaml_conf.apisix.admin_listen.ip or ip
                port = tonumber(yaml_conf.apisix.admin_listen.port) or port
            end

            if ports_to_check[port] ~= nil then
                util.die("admin port ", port, " conflicts with ", ports_to_check[port], "\n")
            end

            admin_server_addr = ip .. ":" .. port
            ports_to_check[port] = "admin"
        end
    end

    local control_server_addr
    if yaml_conf.apisix.enable_control then
        if not yaml_conf.apisix.control then
            if ports_to_check[9090] ~= nil then
                util.die("control port 9090 conflicts with ", ports_to_check[9090], "\n")
            end
            control_server_addr = "127.0.0.1:9090"
            ports_to_check[9090] = "control"
        else
            local ip = yaml_conf.apisix.control.ip
            local port = tonumber(yaml_conf.apisix.control.port)

            if ip == nil then
                ip = "127.0.0.1"
            end

            if not port then
                port = 9090
            end

            if ports_to_check[port] ~= nil then
                util.die("control port ", port, " conflicts with ", ports_to_check[port], "\n")
            end

            control_server_addr = ip .. ":" .. port
            ports_to_check[port] = "control"
        end
    end

    local prometheus_server_addr
    if yaml_conf.plugin_attr.prometheus then
        local prometheus = yaml_conf.plugin_attr.prometheus
        if prometheus.enable_export_server then
            local ip = prometheus.export_addr.ip
            local port = tonumber(prometheus.export_addr.port)

            if ip == nil then
                ip = "127.0.0.1"
            end

            if not port then
                port = 9091
            end

            if ports_to_check[port] ~= nil then
                util.die("prometheus port ", port, " conflicts with ", ports_to_check[port], "\n")
            end

            prometheus_server_addr = ip .. ":" .. port
            ports_to_check[port] = "prometheus"
        end
    end

    local ip_port_to_check = {}

    local function listen_table_insert(listen_table, scheme, ip, port, enable_http2, enable_ipv6)
        if type(ip) ~= "string" then
            util.die(scheme, " listen ip format error, must be string", "\n")
        end

        if type(port) ~= "number" then
            util.die(scheme, " listen port format error, must be number", "\n")
        end

        if ports_to_check[port] ~= nil then
            util.die(scheme, " listen port ", port, " conflicts with ",
                ports_to_check[port], "\n")
        end

        local addr = ip .. ":" .. port

        if ip_port_to_check[addr] == nil then
            table_insert(listen_table,
                    {ip = ip, port = port, enable_http2 = enable_http2})
            ip_port_to_check[addr] = scheme
        end

        if enable_ipv6 then
            ip = "[::]"
            addr = ip .. ":" .. port

            if ip_port_to_check[addr] == nil then
                table_insert(listen_table,
                        {ip = ip, port = port, enable_http2 = enable_http2})
                ip_port_to_check[addr] = scheme
            end
        end
    end

    local node_listen = {}
    -- listen in http, support multiple ports and specific IP, compatible with the original style
    if type(yaml_conf.apisix.node_listen) == "number" then
        listen_table_insert(node_listen, "http", "0.0.0.0", yaml_conf.apisix.node_listen,
                false, yaml_conf.apisix.enable_ipv6)
    elseif type(yaml_conf.apisix.node_listen) == "table" then
        for _, value in ipairs(yaml_conf.apisix.node_listen) do
            if type(value) == "number" then
                listen_table_insert(node_listen, "http", "0.0.0.0", value,
                        false, yaml_conf.apisix.enable_ipv6)
            elseif type(value) == "table" then
                local ip = value.ip
                local port = value.port
                local enable_ipv6 = false
                local enable_http2 = value.enable_http2

                if ip == nil then
                    ip = "0.0.0.0"
                    if yaml_conf.apisix.enable_ipv6 then
                        enable_ipv6 = true
                    end
                end

                if port == nil then
                    port = 9080
                end

                if enable_http2 == nil then
                    enable_http2 = false
                end

                listen_table_insert(node_listen, "http", ip, port,
                        enable_http2, enable_ipv6)
            end
        end
    end
    yaml_conf.apisix.node_listen = node_listen

    local ssl_listen = {}
    -- listen in https, support multiple ports, support specific IP
    for _, value in ipairs(yaml_conf.apisix.ssl.listen) do
        if type(value) == "number" then
            listen_table_insert(ssl_listen, "https", "0.0.0.0", value,
                    yaml_conf.apisix.ssl.enable_http2, yaml_conf.apisix.enable_ipv6)
        elseif type(value) == "table" then
            local ip = value.ip
            local port = value.port
            local enable_ipv6 = false
            local enable_http2 = (value.enable_http2 or yaml_conf.apisix.ssl.enable_http2)

            if ip == nil then
                ip = "0.0.0.0"
                if yaml_conf.apisix.enable_ipv6 then
                    enable_ipv6 = true
                end
            end

            if port == nil then
                port = 9443
            end

            if enable_http2 == nil then
                enable_http2 = false
            end

            listen_table_insert(ssl_listen, "https", ip, port,
                    enable_http2, enable_ipv6)
        end
    end

    -- listen in https, compatible with the original style
    if type(yaml_conf.apisix.ssl.listen_port) == "number" then
        listen_table_insert(ssl_listen, "https", "0.0.0.0", yaml_conf.apisix.ssl.listen_port,
                yaml_conf.apisix.ssl.enable_http2, yaml_conf.apisix.enable_ipv6)
    elseif type(yaml_conf.apisix.ssl.listen_port) == "table" then
        for _, value in ipairs(yaml_conf.apisix.ssl.listen_port) do
            if type(value) == "number" then
                listen_table_insert(ssl_listen, "https", "0.0.0.0", value,
                        yaml_conf.apisix.ssl.enable_http2, yaml_conf.apisix.enable_ipv6)
            end
        end
    end

    yaml_conf.apisix.ssl.listen = ssl_listen

    if yaml_conf.apisix.ssl.ssl_trusted_certificate ~= nil then
        local cert_path = yaml_conf.apisix.ssl.ssl_trusted_certificate
        -- During validation, the path is relative to PWD
        -- When Nginx starts, the path is relative to conf
        -- Therefore we need to check the absolute version instead
        cert_path = pl_path.abspath(cert_path)

        local ok, err = util.is_file_exist(cert_path)
        if not ok then
            util.die(err, "\n")
        end

        yaml_conf.apisix.ssl.ssl_trusted_certificate = cert_path
    end

    local admin_api_mtls = yaml_conf.apisix.admin_api_mtls
    if yaml_conf.apisix.https_admin and
       not (admin_api_mtls and
            admin_api_mtls.admin_ssl_cert and
            admin_api_mtls.admin_ssl_cert ~= "" and
            admin_api_mtls.admin_ssl_cert_key and
            admin_api_mtls.admin_ssl_cert_key ~= "")
    then
        util.die("missing ssl cert for https admin")
    end

    -- enable ssl with place holder crt&key
    yaml_conf.apisix.ssl.ssl_cert = "cert/ssl_PLACE_HOLDER.crt"
    yaml_conf.apisix.ssl.ssl_cert_key = "cert/ssl_PLACE_HOLDER.key"

    local tcp_enable_ssl
    -- compatible with the original style which only has the addr
    if yaml_conf.apisix.stream_proxy and yaml_conf.apisix.stream_proxy.tcp then
        local tcp = yaml_conf.apisix.stream_proxy.tcp
        for i, item in ipairs(tcp) do
            if type(item) ~= "table" then
                tcp[i] = {addr = item}
            else
                if item.tls then
                    tcp_enable_ssl = true
                end
            end
        end
    end

    local dubbo_upstream_multiplex_count = 32
    if yaml_conf.plugin_attr and yaml_conf.plugin_attr["dubbo-proxy"] then
        local dubbo_conf = yaml_conf.plugin_attr["dubbo-proxy"]
        if tonumber(dubbo_conf.upstream_multiplex_count) >= 1 then
            dubbo_upstream_multiplex_count = dubbo_conf.upstream_multiplex_count
        end
    end

    if yaml_conf.apisix.dns_resolver_valid then
        if tonumber(yaml_conf.apisix.dns_resolver_valid) == nil then
            util.die("apisix->dns_resolver_valid should be a number")
        end
    end

    -- Using template.render
    local sys_conf = {
        use_openresty_1_17 = use_openresty_1_17,
        lua_path = env.pkg_path_org,
        lua_cpath = env.pkg_cpath_org,
        os_name = util.trim(util.execute_cmd("uname")),
        apisix_lua_home = env.apisix_home,
        with_module_status = with_module_status,
        use_apisix_openresty = use_apisix_openresty,
        error_log = {level = "warn"},
        enabled_plugins = enabled_plugins,
        dubbo_upstream_multiplex_count = dubbo_upstream_multiplex_count,
        tcp_enable_ssl = tcp_enable_ssl,
        admin_server_addr = admin_server_addr,
        control_server_addr = control_server_addr,
        prometheus_server_addr = prometheus_server_addr,
    }

    if not yaml_conf.apisix then
        util.die("failed to read `apisix` field from yaml file")
    end

    if not yaml_conf.nginx_config then
        util.die("failed to read `nginx_config` field from yaml file")
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
    sys_conf["wasm"] = yaml_conf.wasm


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
        local dns_addrs, err = local_dns_resolver("/etc/resolv.conf")
        if not dns_addrs then
            util.die("failed to import local DNS: ", err, "\n")
        end

        if #dns_addrs == 0 then
            util.die("local DNS is empty\n")
        end

        sys_conf["dns_resolver"] = dns_addrs
    end

    for i, r in ipairs(sys_conf["dns_resolver"]) do
        if r:match(":[^:]*:") then
            -- more than one colon, is IPv6
            if r:byte(1) ~= str_byte('[') then
                -- ensure IPv6 address is always wrapped in []
                sys_conf["dns_resolver"][i] = "[" .. r .. "]"
            end
        end
    end

    local env_worker_processes = getenv("APISIX_WORKER_PROCESSES")
    if env_worker_processes then
        sys_conf["worker_processes"] = floor(tonumber(env_worker_processes))
    end

    if sys_conf["http"]["lua_shared_dicts"] then
        stderr:write("lua_shared_dicts is deprecated, " ..
                     "use custom_lua_shared_dict instead\n")
    end

    local exported_vars = file.get_exported_vars()
    if exported_vars then
        if not sys_conf["envs"] then
            sys_conf["envs"]= {}
        end
        for _, cfg_env in ipairs(sys_conf["envs"]) do
            local cfg_name
            local from = str_find(cfg_env, "=", 1, true)
            if from then
                cfg_name = str_sub(cfg_env, 1, from - 1)
            else
                cfg_name = cfg_env
            end

            exported_vars[cfg_name] = false
        end

        for name, value in pairs(exported_vars) do
            if value then
                table_insert(sys_conf["envs"], name .. "=" .. value)
            end
        end
    end

    -- fix up lua path
    sys_conf["extra_lua_path"] = get_lua_path(yaml_conf.apisix.extra_lua_path)
    sys_conf["extra_lua_cpath"] = get_lua_path(yaml_conf.apisix.extra_lua_cpath)

    local conf_render = template.compile(ngx_tpl)
    local ngxconf = conf_render(sys_conf)

    local ok, err = util.write_file(env.apisix_home .. "/conf/nginx.conf",
                                    ngxconf)
    if not ok then
        util.die("failed to update nginx.conf: ", err, "\n")
    end
end


local function init_etcd(env, args)
    etcd.init(env, args)
end


local function start(env, ...)
    -- Because the worker process started by apisix has "nobody" permission,
    -- it cannot access the `/root` directory. Therefore, it is necessary to
    -- prohibit APISIX from running in the /root directory.
    if env.is_root_path then
        util.die("Error: It is forbidden to run APISIX in the /root directory.\n")
    end

    local cmd_logs = "mkdir -p " .. env.apisix_home .. "/logs"
    util.execute_cmd(cmd_logs)

    -- check running
    local pid_path = env.apisix_home .. "/logs/nginx.pid"
    local pid = util.read_file(pid_path)
    pid = tonumber(pid)
    if pid then
        local lsof_cmd = "lsof -p " .. pid
        local res, err = util.execute_cmd(lsof_cmd)
        if not (res and res == "") then
            if not res then
                print(err)
            else
                print("APISIX is running...")
            end

            return
        end

        print("nginx.pid exists but there's no corresponding process with pid ", pid,
              ", the file will be overwritten")
    end

    local parser = argparse()
    parser:argument("_", "Placeholder")
    parser:option("-c --config", "location of customized config.yaml")
    -- TODO: more logs for APISIX cli could be added using this feature
    parser:flag("--verbose", "show init_etcd debug information")
    local args = parser:parse()

    local customized_yaml = args["config"]
    if customized_yaml then
        profile.apisix_home = env.apisix_home .. "/"
        local local_conf_path = profile:yaml_path("config")

        local err = util.execute_cmd_with_error("mv " .. local_conf_path .. " "
                                                .. local_conf_path .. ".bak")
        if #err > 0 then
            util.die("failed to mv config to backup, error: ", err)
        end
        err = util.execute_cmd_with_error("ln " .. customized_yaml .. " " .. local_conf_path)
        if #err > 0 then
            util.execute_cmd("mv " .. local_conf_path .. ".bak " .. local_conf_path)
            util.die("failed to link customized config, error: ", err)
        end

        print("Use customized yaml: ", customized_yaml)
    end

    init(env)
    init_etcd(env, args)

    util.execute_cmd(env.openresty_args)
end


local function cleanup()
    local local_conf_path = profile:yaml_path("config")
    local bak_exist = io_open(local_conf_path .. ".bak")
    if bak_exist then
        local err = util.execute_cmd_with_error("rm " .. local_conf_path)
        if #err > 0 then
            print("failed to remove customized config, error: ", err)
        end
        err = util.execute_cmd_with_error("mv " .. local_conf_path .. ".bak " .. local_conf_path)
        if #err > 0 then
            util.die("failed to mv original config file, error: ", err)
        end
    end
end


local function test(env, backup_ngx_conf)
    -- backup nginx.conf
    local ngx_conf_path = env.apisix_home .. "/conf/nginx.conf"
    local ngx_conf_exist = util.is_file_exist(ngx_conf_path)
    if ngx_conf_exist then
        local ok, err = os_rename(ngx_conf_path, ngx_conf_path .. ".bak")
        if not ok then
            util.die("failed to backup nginx.conf, error: ", err)
        end
    end

    -- reinit nginx.conf
    init(env)

    local test_cmd = env.openresty_args .. [[ -t -q ]]
    local test_ret = execute((test_cmd))

    -- restore nginx.conf
    if ngx_conf_exist then
        local ok, err = os_rename(ngx_conf_path .. ".bak", ngx_conf_path)
        if not ok then
            util.die("failed to restore original nginx.conf, error: ", err)
        end
    end

    -- When success,
    -- On linux, os.execute returns 0,
    -- On macos, os.execute returns 3 values: true, exit, 0, and we need the first.
    if (test_ret == 0 or test_ret == true) then
        print("configuration test is successful")
        return
    end

    util.die("configuration test failed")
end


local function quit(env)
    cleanup()

    local cmd = env.openresty_args .. [[ -s quit]]
    util.execute_cmd(cmd)
end


local function stop(env)
    cleanup()

    local cmd = env.openresty_args .. [[ -s stop]]
    util.execute_cmd(cmd)
end


local function restart(env)
  -- test configuration
  test(env)
  stop(env)
  start(env)
end


local function reload(env)
    -- reinit nginx.conf
    init(env)

    local test_cmd = env.openresty_args .. [[ -t -q ]]
    -- When success,
    -- On linux, os.execute returns 0,
    -- On macos, os.execute returns 3 values: true, exit, 0, and we need the first.
    local test_ret = execute((test_cmd))
    if (test_ret == 0 or test_ret == true) then
        local cmd = env.openresty_args .. [[ -s reload]]
        execute(cmd)
        return
    end

    print("test openresty failed")
end



local action = {
    help = help,
    version = version,
    init = init,
    init_etcd = etcd.init,
    start = start,
    stop = stop,
    quit = quit,
    restart = restart,
    reload = reload,
    test = test,
}


function _M.execute(env, arg)
    local cmd_action = arg[1]
    if not cmd_action then
        return help()
    end

    if not action[cmd_action] then
        stderr:write("invalid argument: ", cmd_action, "\n")
        return help()
    end

    action[cmd_action](env, arg[2])
end


return _M
