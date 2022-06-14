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


function _M.generate_conf_server(conf)
    if not (conf.deployment and conf.deployment.role == "traditional") then
        return nil
    end

    -- we use proxy even the role is traditional so that we can test the proxy in daily dev
    local servers = conf.deployment.etcd.host
    for i, s in ipairs(servers) do
        local prefix = "http://"
        -- TODO: support https
        if s:find(prefix, 1, true) then
            servers[i] = s:sub(#prefix + 1)
        end
    end

    local conf_render = template.compile([[
    upstream apisix_conf_backend {
        {% for _, addr in ipairs(servers) do %}
        server {* addr *};
        {% end %}
    }
    server {
        listen unix:./conf/config_listen.sock;
        access_log off;
        location / {
            set $upstream_scheme             'http';

            proxy_pass $upstream_scheme://apisix_conf_backend;

            proxy_http_version 1.1;
            proxy_set_header Connection "";
        }
    }
    ]])
    return conf_render({
        servers = servers
    })
end


return _M
