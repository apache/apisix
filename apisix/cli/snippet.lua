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
local template = require("resty.template")
local pl_path = require("pl.path")
local ipairs = ipairs


-- this module provide methods to generate snippets which will be used in the nginx.conf template
local _M = {}
local conf_server_tpl = [[
upstream apisix_conf_backend {
    server 0.0.0.0:80;
    balancer_by_lua_block {
        local conf_server = require("apisix.conf_server")
        conf_server.balancer()
    }
}

{% if trusted_ca_cert then %}
lua_ssl_trusted_certificate {* trusted_ca_cert *};
{% end %}

server {
    {% if control_plane then %}
    {% if directive_prefix == "grpc" then %}
    listen {* control_plane.listen *} ssl http2;
    {% else %}
    listen {* control_plane.listen *} ssl;
    {% end %}
    ssl_certificate {* control_plane.cert *};
    ssl_certificate_key {* control_plane.cert_key *};

    {% if control_plane.client_ca_cert then %}
    ssl_verify_client on;
    ssl_client_certificate {* control_plane.client_ca_cert *};
    {% end %}

    {% else %}
    {% if directive_prefix == "grpc" then %}
    listen unix:{* home *}/conf/config_listen.sock http2;
    {% else %}
    listen unix:{* home *}/conf/config_listen.sock;
    {% end %}
    {% end %}

    access_log off;

    set $upstream_host '';

    access_by_lua_block {
        local conf_server = require("apisix.conf_server")
        conf_server.access()
    }

    location / {
        {% if enable_https then %}
        {* directive_prefix *}_pass {* scheme_name *}s://apisix_conf_backend;
        {* directive_prefix *}_ssl_protocols TLSv1.2 TLSv1.3;
        {* directive_prefix *}_ssl_server_name on;

        {% if etcd_tls_verify then %}
        {* directive_prefix *}_ssl_verify on;
        {* directive_prefix *}_ssl_trusted_certificate {* ssl_trusted_certificate *};
        {% end %}

        {% if sni then %}
        {* directive_prefix *}_ssl_name {* sni *};
        {% else %}
        {* directive_prefix *}_ssl_name $upstream_host;
        {% end %}

        {% if client_cert then %}
        {* directive_prefix *}_ssl_certificate {* client_cert *};
        {* directive_prefix *}_ssl_certificate_key {* client_cert_key *};
        {% end %}

        {% else %}
        {* directive_prefix *}_pass {* scheme_name *}://apisix_conf_backend;
        {% end %}

        {% if scheme_name == "http"  then %}
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        {% end %}

        {* directive_prefix *}_set_header Host $upstream_host;
        {* directive_prefix *}_next_upstream error timeout non_idempotent
            http_500 http_502 http_503 http_504;
    }

    log_by_lua_block {
        local conf_server = require("apisix.conf_server")
        conf_server.log()
    }
}
]]


local function is_grpc_used(env, etcd)
    local is_grpc_available = env.use_apisix_base
    return is_grpc_available and etcd.use_grpc
end


function _M.generate_conf_server(env, conf)
    if not (conf.deployment and (
        conf.deployment.role == "traditional" or
        conf.deployment.role == "control_plane"))
    then
        return nil, nil
    end

    -- we use proxy even the role is traditional so that we can test the proxy in daily dev
    local etcd = conf.deployment.etcd
    local servers = etcd.host
    local enable_https = false
    local prefix = "https://"
    if servers[1]:find(prefix, 1, true) then
        enable_https = true
    end

    for i, s in ipairs(servers) do
        if (s:find(prefix, 1, true) ~= nil) ~= enable_https then
            return nil, "all nodes in the etcd cluster should enable/disable TLS together"
        end

        local _, to = s:find("://", 1, true)
        if not to then
            return nil, "bad etcd endpoint format"
        end
    end

    local control_plane
    if conf.deployment.role == "control_plane" then
        control_plane = conf.deployment.role_control_plane.conf_server
        control_plane.cert = pl_path.abspath(control_plane.cert)
        control_plane.cert_key = pl_path.abspath(control_plane.cert_key)

        if control_plane.client_ca_cert then
            control_plane.client_ca_cert = pl_path.abspath(control_plane.client_ca_cert)
        end
    end

    local trusted_ca_cert
    if conf.deployment.certs then
        if conf.deployment.certs.trusted_ca_cert then
            trusted_ca_cert = pl_path.abspath(conf.deployment.certs.trusted_ca_cert)
        end
    end

    local conf_render = template.compile(conf_server_tpl)
    local tls = etcd.tls
    local client_cert
    local client_cert_key
    local ssl_trusted_certificate
    local etcd_tls_verify
    local use_grpc = is_grpc_used(env, etcd)
    if tls then
        if tls.cert then
            client_cert = pl_path.abspath(tls.cert)
            client_cert_key = pl_path.abspath(tls.key)
        end

        etcd_tls_verify = tls.verify
        if enable_https and etcd_tls_verify then
            if not conf.apisix.ssl.ssl_trusted_certificate then
                return nil, "should set ssl_trusted_certificate if etcd tls verify is enabled"
            end
            ssl_trusted_certificate = pl_path.abspath(conf.apisix.ssl.ssl_trusted_certificate)
        end
    end

    return conf_render({
        sni = tls and tls.sni,
        home = env.apisix_home or ".",
        control_plane = control_plane,
        enable_https = enable_https,
        client_cert = client_cert,
        client_cert_key = client_cert_key,
        trusted_ca_cert = trusted_ca_cert,
        etcd_tls_verify = etcd_tls_verify,
        ssl_trusted_certificate = ssl_trusted_certificate,
        scheme_name = use_grpc and "grpc" or "http",
        directive_prefix = use_grpc and "grpc" or "proxy",
    })
end


return _M
