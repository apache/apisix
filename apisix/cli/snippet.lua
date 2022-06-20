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
        servers[i] = s:sub(to + 1)
    end

    local conf_render = template.compile([[
    upstream apisix_conf_backend {
        {% for _, addr in ipairs(servers) do %}
        server {* addr *};
        {% end %}
    }
    server {
        listen unix:{* home *}/conf/config_listen.sock;
        access_log off;
        location / {
            {% if enable_https then %}
            proxy_pass https://apisix_conf_backend;
            proxy_ssl_server_name on;
            proxy_ssl_protocols TLSv1.2 TLSv1.3;
            {% else %}
            proxy_pass http://apisix_conf_backend;
            {% end %}

            proxy_http_version 1.1;
            proxy_set_header Connection "";
        }
    }
    ]])
    return conf_render({
        servers = servers,
        enable_https = enable_https,
        home = env.apisix_home or ".",
    })
end


return _M
