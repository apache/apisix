#! /usr/bin/lua

local template = require "resty.template"

local ngx_tpl = [=[
master_process on;

worker_processes auto;
worker_cpu_affinity auto;

error_log logs/error.log error;
pid logs/nginx.pid;

worker_rlimit_nofile 20480;

events {
    accept_mutex off;
    worker_connections 10620;
}

worker_shutdown_timeout 1;

http {
    lua_package_path "{*lua_path*};$prefix/lua/?.lua;;";
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
        listen 9080;

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

local function apisix_home()
    local string_gmatch = string.gmatch
    local string_match = string.match
    local io_open = io.open
    local io_close = io.close

    for k, _ in string_gmatch(package.path, "[^;]+") do
        local fpath = string_match(k, "(.*/)")
        fpath = fpath .. "apisix"
        local f = io_open(fpath .. "/conf/nginx.conf")
        if f ~= nil then
            io_close(f)
            return fpath
        end
    end

    return
end

local _M = {version = 0.1}

function _M.help()
    print([[
Usage: apisix <argument>

help:       show this message, then exit
start:      start the apisix server
stop:       stop the apisix server
reload:     reload the apisix server
]])
end

function _M.init()
    -- -- Using template.render
    local func = template.compile(ngx_tpl)
    local ngxconf = func({lua_path = package.path,
                          lua_cpath = package.cpath})

    -- print(ngxconf)

    local home_path = apisix_home()
    if not home_path then
        return error("failed to find home path of apisix")
    end

    local ok, err = write_file(home_path .. "/conf/nginx.conf", ngxconf)
    if not ok then
        return error("failed to update nginx.conf: " .. err)
    else
        print("succeed to update nginx.conf")
    end
end

function _M.start()
    local home_path = apisix_home()
    if not home_path then
        return error("failed to find home path of apisix")
    end

    os.execute([[openresty -p ]] .. home_path)
end

function _M.stop()
    local home_path = apisix_home()
    if not home_path then
        return error("failed to find home path of apisix")
    end

    -- todo: use single to reload
    os.execute([[openresty -p ]] .. home_path .. [[ -s stop]])
end

function _M.reload()
    local home_path = apisix_home()
    if not home_path then
        return error("failed to find home path of apisix")
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

_M[cmd_action]()
