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


-- This was inspired by https://github.com/openresty/resty-cli/blob/master/bin/resty.

return [=[
# Configuration File - Nginx Server Configs
# This is a read-only file, do not try to modify it.
{% if user and user ~= '' then %}
user {* user *};
{% end %}
daemon off;
master_process off;
worker_processes 1;

{% if os_name == "Linux" and enable_cpu_affinity == true then %}
worker_cpu_affinity auto;
{% end %}

error_log stderr {* error_log_level or "warn" *};
pid logs/nginx.pid;

worker_rlimit_nofile {* worker_rlimit_nofile *};

events {
    accept_mutex off;
    worker_connections {* event.worker_connections *};
}

worker_rlimit_core  {* worker_rlimit_core *};

worker_shutdown_timeout {* worker_shutdown_timeout *};

env APISIX_PROFILE;
env PATH; # for searching external plugin runner's binary

# reserved environment variables for configuration
env APISIX_DEPLOYMENT_ETCD_HOST;

{% if envs then %}
{% for _, name in ipairs(envs) do %}
env {*name*};
{% end %}
{% end %}

{% if use_apisix_base then %}
thread_pool grpc-client-nginx-module threads=1;

lua {
    {% if enabled_stream_plugins["prometheus"] then %}
    lua_shared_dict prometheus-metrics {* meta.lua_shared_dict["prometheus-metrics"] *};
    {% end %}
}

{% if enabled_stream_plugins["prometheus"] and not enable_http then %}
http {
    lua_package_path  "{*extra_lua_path*}$prefix/deps/share/lua/5.1/?.lua;$prefix/deps/share/lua/5.1/?/init.lua;]=]
                       .. [=[{*apisix_lua_home*}/?.lua;{*apisix_lua_home*}/?/init.lua;;{*lua_path*};";
    lua_package_cpath "{*extra_lua_cpath*}$prefix/deps/lib64/lua/5.1/?.so;]=]
                      .. [=[$prefix/deps/lib/lua/5.1/?.so;;]=]
                      .. [=[{*lua_cpath*};";
}
{% end %}

{% end %}

{% if enable_http then %}
http {
    # put extra_lua_path in front of the builtin path
    # so user can override the source code
    lua_package_path  "{*extra_lua_path*}$prefix/deps/share/lua/5.1/?.lua;$prefix/deps/share/lua/5.1/?/init.lua;]=]
                       .. [=[{*apisix_lua_home*}/?.lua;{*apisix_lua_home*}/?/init.lua;;{*lua_path*};";
    lua_package_cpath "{*extra_lua_cpath*}$prefix/deps/lib64/lua/5.1/?.so;]=]
                      .. [=[$prefix/deps/lib/lua/5.1/?.so;;]=]
                      .. [=[{*lua_cpath*};";

    {% if max_pending_timers then %}
    lua_max_pending_timers {* max_pending_timers *};
    {% end %}
    {% if max_running_timers then %}
    lua_max_running_timers {* max_running_timers *};
    {% end %}

    lua_shared_dict internal-status {* http.lua_shared_dict["internal-status"] *};
    lua_shared_dict upstream-healthcheck {* http.lua_shared_dict["upstream-healthcheck"] *};
    lua_shared_dict worker-events {* http.lua_shared_dict["worker-events"] *};
    lua_shared_dict lrucache-lock {* http.lua_shared_dict["lrucache-lock"] *};
    lua_shared_dict balancer-ewma {* http.lua_shared_dict["balancer-ewma"] *};
    lua_shared_dict balancer-ewma-locks {* http.lua_shared_dict["balancer-ewma-locks"] *};
    lua_shared_dict balancer-ewma-last-touched-at {* http.lua_shared_dict["balancer-ewma-last-touched-at"] *};
    lua_shared_dict etcd-cluster-health-check {* http.lua_shared_dict["etcd-cluster-health-check"] *}; # etcd health check

    # for discovery shared dict
    {% if discovery_shared_dicts then %}
    {% for key, size in pairs(discovery_shared_dicts) do %}
    lua_shared_dict {*key*} {*size*};
    {% end %}
    {% end %}

    {% if enabled_discoveries["tars"] then %}
    lua_shared_dict tars {* http.lua_shared_dict["tars"] *};
    {% end %}

    {% if enabled_plugins["limit-conn"] then %}
    lua_shared_dict plugin-limit-conn {* http.lua_shared_dict["plugin-limit-conn"] *};
    {% end %}

    {% if enabled_plugins["limit-req"] then %}
    lua_shared_dict plugin-limit-req {* http.lua_shared_dict["plugin-limit-req"] *};
    {% end %}

    {% if enabled_plugins["limit-count"] then %}
    lua_shared_dict plugin-limit-count {* http.lua_shared_dict["plugin-limit-count"] *};
    lua_shared_dict plugin-limit-count-redis-cluster-slot-lock {* http.lua_shared_dict["plugin-limit-count-redis-cluster-slot-lock"] *};
    lua_shared_dict plugin-limit-count-reset-header {* http.lua_shared_dict["plugin-limit-count"] *};
    {% end %}

    {% if enabled_plugins["prometheus"] and not enabled_stream_plugins["prometheus"] then %}
    lua_shared_dict prometheus-metrics {* http.lua_shared_dict["prometheus-metrics"] *};
    {% end %}

    {% if enabled_plugins["skywalking"] then %}
    lua_shared_dict tracing_buffer {* http.lua_shared_dict.tracing_buffer *}; # plugin: skywalking
    {% end %}

    {% if enabled_plugins["api-breaker"] then %}
    lua_shared_dict plugin-api-breaker {* http.lua_shared_dict["plugin-api-breaker"] *};
    {% end %}

    {% if enabled_plugins["openid-connect"] or enabled_plugins["authz-keycloak"] then %}
    # for openid-connect and authz-keycloak plugin
    lua_shared_dict discovery {* http.lua_shared_dict["discovery"] *}; # cache for discovery metadata documents
    {% end %}

    {% if enabled_plugins["openid-connect"] then %}
    # for openid-connect plugin
    lua_shared_dict jwks {* http.lua_shared_dict["jwks"] *}; # cache for JWKs
    lua_shared_dict introspection {* http.lua_shared_dict["introspection"] *}; # cache for JWT verification results
    {% end %}

    {% if enabled_plugins["cas-auth"] then %}
    lua_shared_dict cas_sessions {* http.lua_shared_dict["cas-auth"] *};
    {% end %}

    {% if enabled_plugins["authz-keycloak"] then %}
    # for authz-keycloak
    lua_shared_dict access-tokens {* http.lua_shared_dict["access-tokens"] *}; # cache for service account access tokens
    {% end %}

    {% if enabled_plugins["ext-plugin-pre-req"] or enabled_plugins["ext-plugin-post-req"] then %}
    lua_shared_dict ext-plugin {* http.lua_shared_dict["ext-plugin"] *}; # cache for ext-plugin
    {% end %}

    {% if config_center == "xds" then %}
    lua_shared_dict xds-config  10m;
    lua_shared_dict xds-config-version  1m;
    {% end %}

    # for custom shared dict
    {% if http.custom_lua_shared_dict then %}
    {% for cache_key, cache_size in pairs(http.custom_lua_shared_dict) do %}
    lua_shared_dict {*cache_key*} {*cache_size*};
    {% end %}
    {% end %}

    {% if enabled_plugins["error-log-logger"] then %}
        lua_capture_error_log  10m;
    {% end %}

    lua_ssl_verify_depth 5;
    ssl_session_timeout 86400;

    {% if http.underscores_in_headers then %}
    underscores_in_headers {* http.underscores_in_headers *};
    {%end%}

    lua_socket_log_errors off;

    resolver {% for _, dns_addr in ipairs(dns_resolver or {}) do %} {*dns_addr*} {% end %} {% if dns_resolver_valid then %} valid={*dns_resolver_valid*}{% end %} ipv6={% if enable_ipv6 then %}on{% else %}off{% end %};
    resolver_timeout {*resolver_timeout*};

    lua_http10_buffering off;

    lua_regex_match_limit 100000;
    lua_regex_cache_max_entries 8192;

    access_log off;

    open_file_cache  max=1000 inactive=60;
    client_max_body_size {* http.client_max_body_size *};
    keepalive_timeout {* http.keepalive_timeout *};
    client_header_timeout {* http.client_header_timeout *};
    client_body_timeout {* http.client_body_timeout *};
    send_timeout {* http.send_timeout *};
    variables_hash_max_size {* http.variables_hash_max_size *};

    server_tokens off;

    include mime.types;
    charset {* http.charset *};

    {% if http.real_ip_header then %}
    real_ip_header {* http.real_ip_header *};
    {% end %}

    {% if http.real_ip_recursive then %}
    real_ip_recursive {* http.real_ip_recursive *};
    {% end %}

    {% if http.real_ip_from then %}
    {% for _, real_ip in ipairs(http.real_ip_from) do %}
    set_real_ip_from {*real_ip*};
    {% end %}
    {% end %}

    {% if ssl.ssl_trusted_certificate ~= nil then %}
    lua_ssl_trusted_certificate {* ssl.ssl_trusted_certificate *};
    {% end %}

    {% if use_apisix_base then %}
    apisix_delay_client_max_body_check on;
    apisix_mirror_on_demand on;
    {% end %}

    {% if wasm then %}
    wasm_vm wasmtime;
    {% end %}

    init_by_lua_block {
        require "resty.core"

        {% if lua_module_hook then %}
        require "{* lua_module_hook *}"
        {% end %}
        apisix = require("apisix")

        local dns_resolver = { {% for _, dns_addr in ipairs(dns_resolver or {}) do %} "{*dns_addr*}", {% end %} }
        local args = {
            dns_resolver = dns_resolver,
        }
        apisix.http_init(args)

        -- set apisix_lua_home into constants module
        -- it may be used by plugins to determine the work path of apisix
        local constants = require("apisix.constants")
        constants.apisix_lua_home = "{*apisix_lua_home*}"

        local stdout = io.stdout
        local ngx_null = ngx.null
        local maxn = table.maxn
        local unpack = unpack
        local concat = table.concat

        local expand_table
        function expand_table(src, inplace)
            local n = maxn(src)
            local dst = inplace and src or {}
            for i = 1, n do
                local arg = src[i]
                local typ = type(arg)
                if arg == nil then
                    dst[i] = "nil"

                elseif typ == "boolean" then
                    if arg then
                        dst[i] = "true"
                    else
                        dst[i] = "false"
                    end

                elseif arg == ngx_null then
                    dst[i] = "null"

                elseif typ == "table" then
                    dst[i] = expand_table(arg, false)

                elseif typ ~= "string" then
                    dst[i] = tostring(arg)

                else
                    dst[i] = arg
                end
            end
            return concat(dst)
        end

        local function output(...)
            local args = {...}

            return stdout:write(expand_table(args, true))
        end

        ngx.orig_print = ngx.print
        ngx.print = output

        ngx.orig_say = ngx.say
        ngx.say = function (...)
            local ok, err = output(...)
            if ok then
                return stdout:write("\n")
            end
            return ok, err
        end
        print = ngx.say

        ngx.flush = function (...) return stdout:flush() end
        -- we cannot close stdout here due to a bug in Lua:
        ngx.eof = function (...) return true end
        ngx.orig_exit = ngx.exit
        ngx.exit = os.exit
    }

    init_worker_by_lua_block {
        local exit = os.exit
        local stderr = io.stderr
        local ffi = require "ffi"

        local function handle_err(err)
            if err then
                err = string.gsub(err, "^init_worker_by_lua:%d+: ", "")
                stderr:write("ERROR: ", err, "\\n")
            end
            return exit(1)
        end

        local ok, err = pcall(function ()
            local signal_graceful_exit = require("ngx.process").signal_graceful_exit

            local gen = assert(loadstring({*script*}, "script"))

            local ok, err = ngx.timer.at(0, function ()
                local ok, err = xpcall(gen, function (err)
                    -- level 3: we skip this function and the
                    -- error() call itself in our stacktrace
                    local trace = debug.traceback(err, 3)
                    return handle_err(trace)
                end)
                if not ok then
                    return handle_err(err)
                end
                if ffi.abi("win") then
                    return exit(0)
                end
                signal_graceful_exit()
            end)
        end)

        if not ok then
            return handle_err(err)
        end
    }

    exit_worker_by_lua_block {
        apisix.http_exit_worker()
    }
}
{% end %}
]=]
