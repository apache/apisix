#! /usr/bin/lua

local yaml = require("apisix.lua.apisix.core.yaml")
local template = require("resty.template")

local ngx_tpl = [=[
master_process on;

worker_processes auto;
{% if os_name == "Linux" then %}
worker_cpu_affinity auto;
{% end %}

error_log logs/error.log error;
pid logs/nginx.pid;

worker_rlimit_nofile 20480;

events {
    accept_mutex off;
    worker_connections 10620;
}

worker_shutdown_timeout 1;

http {
    lua_package_path "$prefix/lua/?.lua;;{*lua_path*};";
    lua_package_cpath "{*lua_cpath*};;";

    lua_shared_dict plugin-limit-req    10m;
    lua_shared_dict plugin-limit-count  10m;
    lua_shared_dict prometheus_metrics  10m;

    lua_ssl_verify_depth 5;
    ssl_session_timeout 86400;

    lua_socket_log_errors off;

    resolver ipv6=off local=on;
    resolver_timeout 5;

    lua_http10_buffering off;

    log_format main '$remote_addr - $remote_user [$time_local] $http_host "$request" $status $body_bytes_sent $request_time "$http_referer" "$http_user_agent" $upstream_addr $upstream_status $upstream_response_time';

    access_log logs/access.log main buffer=32768 flush=3;
    client_max_body_size 0;

    server_tokens off;
    more_set_headers 'Server: APISIX web server';

    upstream backend {
        server 0.0.0.1;
        balancer_by_lua_block {
            apisix.balancer_phase()
        }

        keepalive 32;
    }

    init_by_lua_block {
        require "resty.core"
        apisix = require("apisix")
        apisix.init()
    }

    init_worker_by_lua_block {
        apisix.init_worker()
    }

    server {
        listen {* node_listen *};

        include mime.types;

        location = /apisix.com/nginx_status {
            internal;
            access_log off;
            stub_status;
        }

        location / {
            set $upstream_scheme             'http';
            set $upstream_host               $host;
            set $upstream_upgrade            '';
            set $upstream_connection         '';
            set $upstream_uri                '';

            rewrite_by_lua_block {
                apisix.rewrite_phase()
            }

            access_by_lua_block {
                apisix.access_phase()
            }

            proxy_http_version 1.1;
            proxy_set_header   Host              $upstream_host;
            proxy_set_header   Upgrade           $upstream_upgrade;
            proxy_set_header   Connection        $upstream_connection;
            proxy_set_header   X-Real-IP         $remote_addr;
            proxy_pass_header  Server;
            proxy_pass_header  Date;
            proxy_pass         $upstream_scheme://backend$upstream_uri;

            header_filter_by_lua_block {
                apisix.header_filter_phase()
            }

            log_by_lua_block {
                apisix.log_phase()
            }
        }
    }
}
]=]

local function write_file(file_path, data)
    local file = io.open(file_path, "w+")
    if not file then
        return false, "failed to open file: " .. file_path
    end

    file:write(data)
    file:close()
    return true
end

local function read_file(file_path)
    local file = io.open(file_path, "rb")
    if not file then
        return false, "failed to open file: " .. file_path
    end

    local data = file:read("*all")
    file:close()
    return data
end

local function apisix_home()
    local string_gmatch = string.gmatch
    local string_match = string.match
    local io_open = io.open
    local io_close = io.close

    for k, _ in string_gmatch(package.path, "[^;]+") do
        local fpath = string_match(k, "(.*/)")
        fpath = fpath .. "apisix"
        -- print("fpath: ", fpath .. "/conf/config.yaml")
        local f = io_open(fpath .. "/conf/config.yaml")
        if f ~= nil then
            io_close(f)
            return fpath
        end
    end

    return
end

local function trim(s)
  return (s:gsub("^%s*(.-)%s*$", "%1"))
end

local function exec(command)
    local t= io.popen(command)
    local res = t:read("*all")
    t:close()
    return trim(res)
end

local function read_yaml_conf()
    local home_path = apisix_home()
    local ymal_conf, err = read_file(home_path .. "/conf/config.yaml")
    if not ymal_conf then
        return nil, err
    end

    return yaml.parse(ymal_conf)
end

local _M = {version = 0.1}

function _M.help()
    print([[
Usage: apisix [action] <argument>

help:       show this message, then exit
init:       initialize the local nginx.conf
init_etcd:  initialize the data of etcd
start:      start the apisix server
stop:       stop the apisix server
reload:     reload the apisix server
]])
end

local function init()
    -- read_yaml_conf
    local yaml_conf, err = read_yaml_conf()
    if not yaml_conf then
        error("failed to read local yaml config of apisix: " .. err)
    end
    -- print("etcd: ", yaml_conf.etcd.host)

    -- -- Using template.render
    local func = template.compile(ngx_tpl)
    local ngxconf = func({
        lua_path = package.path,
        lua_cpath = package.cpath,
        os_name = exec("uname"),
        node_listen = yaml_conf.apisix.node_listen,
    })

    -- print(ngxconf)

    local home_path = apisix_home()
    if not home_path then
        error("failed to find home path of apisix")
    end

    local ok, err = write_file(home_path .. "/conf/nginx.conf", ngxconf)
    if not ok then
        error("failed to update nginx.conf: " .. err)
    end
end
_M.init = init

local function init_etcd(show_output)
    -- read_yaml_conf
    local yaml_conf, err = read_yaml_conf()
    if not yaml_conf then
        error("failed to read local yaml config of apisix: " .. err)
    end

    local etcd_conf = yaml_conf.etcd
    local uri = etcd_conf.host .. etcd_conf.prefix

    for _, dir_name in ipairs({"/routes", "/upstreams", "/services"}) do
        local cmd = "curl " .. uri .. dir_name
                    .. "?prev_exist=false -X PUT -d dir=true 2>&1"
        local res = exec(cmd)
        if not res:find([[index]], 1, true)
           and not res:find([[createdIndex]], 1, true) then
            error(cmd .. "\n" .. res)
        end

        if show_output then
            print(cmd)
            print(res)
        end
    end
end
_M.init_etcd = init_etcd

function _M.start(...)
    init(...)
    init_etcd(...)

    local home_path = apisix_home()
    if not home_path then
        error("failed to find home path of apisix")
    end

    os.execute([[openresty -p ]] .. home_path)
end

function _M.stop()
    local home_path = apisix_home()
    if not home_path then
        error("failed to find home path of apisix")
    end

    -- todo: use single to reload
    os.execute([[openresty -p ]] .. home_path .. [[ -s stop]])
end

function _M.reload()
    local home_path = apisix_home()
    if not home_path then
        error("failed to find home path of apisix")
    end

    -- todo: use single to reload
    os.execute([[openresty -p ]] .. home_path .. [[ -s reload]])
end

local cmd_action = arg[1]
if not cmd_action then
    return _M.help()
end

if not _M[cmd_action] then
    print("invalid argument: ", cmd_action, "\n")
    return
end

_M[cmd_action](arg[2])
