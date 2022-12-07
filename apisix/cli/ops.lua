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
local cli_ip = require("apisix.cli.ip")
local snippet = require("apisix.cli.snippet")
local profile = require("apisix.core.profile")
local template = require("resty.template")
local argparse = require("argparse")
local pl_path = require("pl.path")
local lfs = require("lfs")
local signal = require("posix.signal")
local errno = require("posix.errno")

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
local os_remove = os.remove
local table_insert = table.insert
local table_remove = table.remove
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
test:       test the generated nginx.conf
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
    if env.ulimit ~= "unlimited" and env.ulimit <= min_ulimit then
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
    local allow_admin = yaml_conf.deployment.admin and
        yaml_conf.deployment.admin.allow_admin
    if yaml_conf.apisix.enable_admin and allow_admin then
        for _, allow_ip in ipairs(allow_admin) do
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
        local admin_key = yaml_conf.deployment.admin
        if admin_key then
            admin_key = admin_key.admin_key
        end

        if type(admin_key) ~= "table" or #admin_key == 0
        then
            util.die(help:format("ERROR: missing valid Admin API token."))
        end

        for _, admin in ipairs(admin_key) do
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

    if yaml_conf.deployment.admin then
        local admin_api_mtls = yaml_conf.deployment.admin.admin_api_mtls
        local https_admin = yaml_conf.deployment.admin.https_admin
        if https_admin and not (admin_api_mtls and
            admin_api_mtls.admin_ssl_cert and
            admin_api_mtls.admin_ssl_cert ~= "" and
            admin_api_mtls.admin_ssl_cert_key and
            admin_api_mtls.admin_ssl_cert_key ~= "")
        then
            util.die("missing ssl cert for https admin")
        end
    end

    if yaml_conf.apisix.enable_admin and
        yaml_conf.deployment.config_provider == "yaml"
    then
        util.die("ERROR: Admin API can only be used with etcd config_provider.\n")
    end

    local or_ver = get_openresty_version()
    if or_ver == nil then
        util.die("can not find openresty\n")
    end

    local need_ver = "1.19.3"
    if not version_greater_equal(or_ver, need_ver) then
        util.die("openresty version must >=", need_ver, " current ", or_ver, "\n")
    end

    local or_info = env.openresty_info
    if not or_info:find("http_stub_status_module", 1, true) then
        util.die("'http_stub_status_module' module is missing in ",
                 "your openresty, please check it out.\n")
    end

    local enable_http = true
    if not yaml_conf.apisix.enable_admin and yaml_conf.apisix.stream_proxy and
        yaml_conf.apisix.stream_proxy.only ~= false
    then
        enable_http = false
    end

    local enabled_discoveries = {}
    for name in pairs(yaml_conf.discovery or {}) do
        enabled_discoveries[name] = true
    end

    local enabled_plugins = {}
    for i, name in ipairs(yaml_conf.plugins or {}) do
        enabled_plugins[name] = true
    end

    local enabled_stream_plugins = {}
    for i, name in ipairs(yaml_conf.stream_plugins or {}) do
        enabled_stream_plugins[name] = true
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
                local _ip = cli_ip:new(ip)
                if _ip then
                    if _ip:is_loopback() or _ip:is_unspecified() then
                        pass_real_client_ip = true
                    end
                end
            end
        end

        if not pass_real_client_ip then
            util.die("missing loopback or unspecified in the nginx_config.http.real_ip_from" ..
                     " for plugin batch-requests\n")
        end
    end

    local ports_to_check = {}

    local function validate_and_get_listen_addr(port_name, default_ip, configured_ip,
                                                default_port, configured_port)
        local ip = configured_ip or default_ip
        local port = tonumber(configured_port) or default_port
        if ports_to_check[port] ~= nil then
            util.die(port_name .. " ", port, " conflicts with ", ports_to_check[port], "\n")
        end
        ports_to_check[port] = port_name
        return ip .. ":" .. port
    end

    -- listen in admin use a separate port, support specific IP, compatible with the original style
    local admin_server_addr
    if yaml_conf.apisix.enable_admin then
        local ip = yaml_conf.deployment.admin.admin_listen.ip
        local port = yaml_conf.deployment.admin.admin_listen.port
        admin_server_addr = validate_and_get_listen_addr("admin port", "0.0.0.0", ip,
                                                          9180, port)
    end

    local control_server_addr
    if yaml_conf.apisix.enable_control then
        if not yaml_conf.apisix.control then
            control_server_addr = validate_and_get_listen_addr("control port", "127.0.0.1", nil,
                                          9090, nil)
        else
            control_server_addr = validate_and_get_listen_addr("control port", "127.0.0.1",
                                          yaml_conf.apisix.control.ip,
                                          9090, yaml_conf.apisix.control.port)
        end
    end

    local prometheus_server_addr
    if yaml_conf.plugin_attr.prometheus then
        local prometheus = yaml_conf.plugin_attr.prometheus
        if prometheus.enable_export_server then
            prometheus_server_addr = validate_and_get_listen_addr("prometheus port", "127.0.0.1",
                                             prometheus.export_addr.ip,
                                             9091, prometheus.export_addr.port)
        end
    end

    if enabled_stream_plugins["prometheus"] and not prometheus_server_addr then
        util.die("L4 prometheus metric should be exposed via export server\n")
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
            port = 9443
        end

        if enable_http2 == nil then
            enable_http2 = false
        end

        listen_table_insert(ssl_listen, "https", ip, port,
                enable_http2, enable_ipv6)
    end

    yaml_conf.apisix.ssl.listen = ssl_listen

    if yaml_conf.apisix.ssl.ssl_trusted_certificate ~= nil then
        local cert_path = yaml_conf.apisix.ssl.ssl_trusted_certificate
        -- During validation, the path is relative to PWD
        -- When Nginx starts, the path is relative to conf
        -- Therefore we need to check the absolute version instead
        cert_path = pl_path.abspath(cert_path)

        if not pl_path.exists(cert_path) then
            util.die("certificate path", cert_path, "doesn't exist\n")
        end

        yaml_conf.apisix.ssl.ssl_trusted_certificate = cert_path
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

    local proxy_mirror_timeouts
    if yaml_conf.plugin_attr["proxy-mirror"] then
        proxy_mirror_timeouts = yaml_conf.plugin_attr["proxy-mirror"].timeout
    end

    local conf_server, err = snippet.generate_conf_server(env, yaml_conf)
    if err then
        util.die(err, "\n")
    end

    if yaml_conf.deployment and yaml_conf.deployment.role then
        local role = yaml_conf.deployment.role
        env.deployment_role = role

        if role == "control_plane" and not admin_server_addr then
            local listen = node_listen[1]
            admin_server_addr = str_format("%s:%s", listen.ip, listen.port)
        end
    end

    -- Using template.render
    local sys_conf = {
        lua_path = env.pkg_path_org,
        lua_cpath = env.pkg_cpath_org,
        os_name = util.trim(util.execute_cmd("uname")),
        apisix_lua_home = env.apisix_home,
        deployment_role = env.deployment_role,
        use_apisix_base = env.use_apisix_base,
        error_log = {level = "warn"},
        enable_http = enable_http,
        enabled_discoveries = enabled_discoveries,
        enabled_plugins = enabled_plugins,
        enabled_stream_plugins = enabled_stream_plugins,
        dubbo_upstream_multiplex_count = dubbo_upstream_multiplex_count,
        tcp_enable_ssl = tcp_enable_ssl,
        admin_server_addr = admin_server_addr,
        control_server_addr = control_server_addr,
        prometheus_server_addr = prometheus_server_addr,
        proxy_mirror_timeouts = proxy_mirror_timeouts,
        conf_server = conf_server,
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
    if yaml_conf.deployment.admin then
        for k,v in pairs(yaml_conf.deployment.admin) do
            sys_conf[k] = v
        end
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

        -- check if the dns_resolver is ipv6 address with zone_id
        -- Nginx does not support this form
        if r:find("%%") then
            stderr:write("unsupported DNS resolver: " .. r ..
                         ", would ignore this item\n")
            table_remove(sys_conf["dns_resolver"], i)
        end
    end

    local env_worker_processes = getenv("APISIX_WORKER_PROCESSES")
    if env_worker_processes then
        sys_conf["worker_processes"] = floor(tonumber(env_worker_processes))
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

    -- inject kubernetes discovery shared dict and environment variable
    if enabled_discoveries["kubernetes"] then

        if not sys_conf["discovery_shared_dicts"] then
            sys_conf["discovery_shared_dicts"] = {}
        end

        local kubernetes_conf = yaml_conf.discovery["kubernetes"]

        local inject_environment = function(conf, envs)
            local keys = {
                conf.service.host,
                conf.service.port,
            }

            if conf.client.token then
                table_insert(keys, conf.client.token)
            end

            if conf.client.token_file then
                table_insert(keys, conf.client.token_file)
            end

            for _, key in ipairs(keys) do
                if #key > 3 then
                    local first, second = str_byte(key, 1, 2)
                    if first == str_byte('$') and second == str_byte('{') then
                        local last = str_byte(key, #key)
                        if last == str_byte('}') then
                            envs[str_sub(key, 3, #key - 1)] = ""
                        end
                    end
                end
            end

        end

        local envs = {}
        if #kubernetes_conf == 0 then
            sys_conf["discovery_shared_dicts"]["kubernetes"] = kubernetes_conf.shared_size
            inject_environment(kubernetes_conf, envs)
        else
            for _, item in ipairs(kubernetes_conf) do
                sys_conf["discovery_shared_dicts"]["kubernetes-" .. item.id] = item.shared_size
                inject_environment(item, envs)
            end
        end

        if not sys_conf["envs"] then
            sys_conf["envs"] = {}
        end

        for item in pairs(envs) do
            table_insert(sys_conf["envs"], item)
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

    local logs_path = env.apisix_home .. "/logs"
    if not pl_path.exists(logs_path) then
        local _, err = pl_path.mkdir(logs_path)
        if err ~= nil then
            util.die("failed to mkdir ", logs_path, ", error: ", err)
        end
    elseif not pl_path.isdir(logs_path) and not pl_path.islink(logs_path) then
        util.die(logs_path, " is not directory nor symbol link")
    end

    -- check running
    local pid_path = env.apisix_home .. "/logs/nginx.pid"
    local pid = util.read_file(pid_path)
    pid = tonumber(pid)
    if pid then
        if pid <= 0 then
            print("invalid pid")
            return
        end

        local signone = 0

        local ok, err, err_no = signal.kill(pid, signone)
        if ok then
            print("APISIX is running...")
            return
        -- no such process
        elseif err_no ~= errno.ESRCH then
            print(err)
            return
        end

        print("nginx.pid exists but there's no corresponding process with pid ", pid,
              ", the file will be overwritten")
    end

    -- start a new APISIX instance

    local conf_server_sock_path = env.apisix_home .. "/conf/config_listen.sock"
    if pl_path.exists(conf_server_sock_path) then
        -- remove stale sock (if exists) so that APISIX can start
        local ok, err = os_remove(conf_server_sock_path)
        if not ok then
            util.die("failed to remove stale conf server sock file, error: ", err)
        end
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
        local local_conf_path_bak = local_conf_path .. ".bak"

        local ok, err = os_rename(local_conf_path, local_conf_path_bak)
        if not ok then
            util.die("failed to backup config, error: ", err)
        end
        local ok, err1 = lfs.link(customized_yaml, local_conf_path)
        if not ok then
            ok, err = os_rename(local_conf_path_bak,  local_conf_path)
            if not ok then
                util.die("failed to recover original config file, error: ", err)
            end
            util.die("failed to link customized config, error: ", err1)
        end

        print("Use customized yaml: ", customized_yaml)
    end

    init(env)

    if env.deployment_role ~= "data_plane" then
        init_etcd(env, args)
    end

    util.execute_cmd(env.openresty_args)
end


local function cleanup()
    local local_conf_path = profile:yaml_path("config")
    local local_conf_path_bak = local_conf_path .. ".bak"
    if pl_path.exists(local_conf_path_bak) then
        local ok, err = os_remove(local_conf_path)
        if not ok then
            print("failed to remove customized config, error: ", err)
        end
        ok, err = os_rename(local_conf_path_bak,  local_conf_path)
        if not ok then
            util.die("failed to recover original config file, error: ", err)
        end
    end
end


local function test(env, backup_ngx_conf)
    -- backup nginx.conf
    local ngx_conf_path = env.apisix_home .. "/conf/nginx.conf"
    local ngx_conf_path_bak = ngx_conf_path .. ".bak"
    local ngx_conf_exist = pl_path.exists(ngx_conf_path)
    if ngx_conf_exist then
        local ok, err = os_rename(ngx_conf_path, ngx_conf_path_bak)
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
        local ok, err = os_rename(ngx_conf_path_bak, ngx_conf_path)
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
