#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

use t::APISIX 'no_plan';

log_level("info");
repeat_each(1);
no_long_string();
no_root_location();

run_tests();

__DATA__

=== TEST 1: no service account key -> metadata server (Workload Identity) used by default
--- config
    location /t {
        content_by_lua_block {
            local google_oauth = require("apisix.utils.google-cloud-oauth")
            local oauth = google_oauth.new({})
            ngx.say("use_metadata_server: ", tostring(oauth.use_metadata_server))
        }
    }
--- request
GET /t
--- response_body
use_metadata_server: true



=== TEST 2: service account key present -> JWT flow, metadata server not used
--- config
    location /t {
        content_by_lua_block {
            local google_oauth = require("apisix.utils.google-cloud-oauth")
            local oauth = google_oauth.new({
                client_email = "sa@example.iam.gserviceaccount.com",
                private_key = "-----BEGIN PRIVATE KEY-----\nfake\n-----END PRIVATE KEY-----\n",
            })
            ngx.say("use_metadata_server: ", tostring(oauth.use_metadata_server))
        }
    }
--- request
GET /t
--- response_body
use_metadata_server: false



=== TEST 3: fetch access token from the metadata server
--- config
    location = /computeMetadata/v1/instance/service-accounts/default/token {
        content_by_lua_block {
            local flavor = ngx.req.get_headers()["Metadata-Flavor"]
            if flavor ~= "Google" then
                ngx.status = 403
                ngx.say("missing Metadata-Flavor header")
                return
            end
            ngx.header["Content-Type"] = "application/json"
            ngx.say('{"access_token":"ya29.metadata-token",'
                    .. '"expires_in":3599,"token_type":"Bearer"}')
        }
    }
    location /t {
        content_by_lua_block {
            local google_oauth = require("apisix.utils.google-cloud-oauth")
            local oauth = google_oauth.new({
                metadata_host = "http://127.0.0.1:" .. ngx.var.server_port
            })
            local token = oauth:generate_access_token()
            ngx.say("token: ", token)
            ngx.say("token_type: ", oauth.access_token_type)
            ngx.say("ttl: ", oauth.access_token_ttl)
        }
    }
--- request
GET /t
--- response_body
token: ya29.metadata-token
token_type: Bearer
ttl: 3599



=== TEST 4: explicit use_metadata_server flag fetches from the metadata server
--- config
    location = /computeMetadata/v1/instance/service-accounts/default/token {
        content_by_lua_block {
            ngx.header["Content-Type"] = "application/json"
            ngx.say('{"access_token":"ya29.explicit",'
                    .. '"expires_in":100,"token_type":"Bearer"}')
        }
    }
    location /t {
        content_by_lua_block {
            local google_oauth = require("apisix.utils.google-cloud-oauth")
            local oauth = google_oauth.new({
                use_metadata_server = true,
                metadata_host = "http://127.0.0.1:" .. ngx.var.server_port
            })
            ngx.say("token: ", oauth:generate_access_token())
        }
    }
--- request
GET /t
--- response_body
token: ya29.explicit



=== TEST 5: metadata server host can be set via GCE_METADATA_HOST env
--- main_config
env GCE_METADATA_HOST=127.0.0.1:1984;
--- config
    location = /computeMetadata/v1/instance/service-accounts/default/token {
        content_by_lua_block {
            ngx.header["Content-Type"] = "application/json"
            ngx.say('{"access_token":"ya29.from-env",'
                    .. '"expires_in":42,"token_type":"Bearer"}')
        }
    }
    location /t {
        content_by_lua_block {
            local google_oauth = require("apisix.utils.google-cloud-oauth")
            local oauth = google_oauth.new({})
            ngx.say("token: ", oauth:generate_access_token())
        }
    }
--- request
GET /t
--- response_body
token: ya29.from-env
