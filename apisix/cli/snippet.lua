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


function _M.generate_conf_server(env, conf)
    if not (conf.deployment and conf.deployment.role == "traditional") then
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
    -- there is not a compatible way to verify upstream TLS like the one we do in cosocket
    -- so here we just ignore it as the verification is already done in the init phase
    for i, s in ipairs(servers) do
        if (s:find(prefix, 1, true) ~= nil) ~= enable_https then
            return nil, "all nodes in the etcd cluster should enable/disable TLS together"
        end

        local _, to = s:find("://", 1, true)
        if not to then
            return nil, "bad etcd endpoint format"
        end
    end

    local conf_render = template.compile([[
    upstream apisix_conf_backend {
        server 0.0.0.0:80;
        balancer_by_lua_block {
            local conf_server = require("apisix.conf_server")
            conf_server.balancer()
        }
    }
    server {
        listen unix:{* home *}/conf/config_listen.sock;
        access_log off;

        set $upstream_host '';

        access_by_lua_block {
            local conf_server = require("apisix.conf_server")
            conf_server.access()
        }

        location / {
            {% if enable_https then %}
            proxy_pass https://apisix_conf_backend;
            proxy_ssl_server_name on;
            {% if sni then %}
            proxy_ssl_name {* sni *};
            {% else %}
            proxy_ssl_name $upstream_host;
            {% end %}
            proxy_ssl_protocols TLSv1.2 TLSv1.3;
            {% if client_cert then %}
            proxy_ssl_certificate {* client_cert *};
            proxy_ssl_certificate_key {* client_cert_key *};
            {% end %}
            {% else %}
            proxy_pass http://apisix_conf_backend;
            {% end %}

            proxy_http_version 1.1;
            proxy_set_header Connection "";
            proxy_set_header Host $upstream_host;
        }

        log_by_lua_block {
            local conf_server = require("apisix.conf_server")
            conf_server.log()
        }
    }
    ]])

    local tls = etcd.tls
    local client_cert
    local client_cert_key
    if tls and tls.cert then
        client_cert = pl_path.abspath(tls.cert)
        client_cert_key = pl_path.abspath(tls.key)
    end

    return conf_render({
        sni = etcd.tls and etcd.tls.sni,
        enable_https = enable_https,
        home = env.apisix_home or ".",
        client_cert = client_cert,
        client_cert_key = client_cert_key,
    })
end


return _M
