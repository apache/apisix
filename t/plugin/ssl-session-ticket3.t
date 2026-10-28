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
use t::APISIX;

my $nginx_binary = $ENV{'TEST_NGINX_BINARY'} || 'nginx';
my $version = eval { `$nginx_binary -V 2>&1` };

if ($version !~ m/\/apisix-nginx-module/) {
    plan(skip_all => "apisix-nginx-module not installed");
} else {
    plan('no_plan');
}

repeat_each(1);
no_long_string();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    my $yaml_config = $block->yaml_config // <<_EOC_;
apisix:
    node_listen: 1984
    proxy_mode: http&stream
    stream_proxy:
        tcp:
            - 9100
deployment:
    role: data_plane
    role_data_plane:
        config_provider: yaml
_EOC_

    $block->set_value("yaml_config", $yaml_config);

    if (!defined $block->extra_yaml_config) {
        $block->set_value("extra_yaml_config", <<_EOC_);
plugin_attr:
  ssl-session-ticket:
    enabled: true
    key_source: external
_EOC_
    }

    my $config = <<_EOC_;
    location /t {
        content_by_lua_block {
            local h = require("lib.ssl_session_ticket")
            local snap = h.wait_state(function(s) return s.state ~= "pending" end)
            local keys = {}
            for i, k in ipairs(snap.keys) do
                keys[i] = k == h.key(i) and "k" .. i or "?"
            end
            ngx.say(snap.state, " [", table.concat(keys, ","), "] ",
                    snap.origin and snap.origin.source, " ",
                    snap.origin and snap.origin.disabled, " ",
                    snap.origin and snap.origin.revision and "has revision", " ",
                    snap.error)
        }
    }
_EOC_

    if (!defined $block->config) {
        $block->set_value("config", $config);
    }
});

run_tests;

__DATA__

=== TEST 1: a record without origin is an external set, enabled by the local policy
--- apisix_yaml
plugin_metadata:
  - id: ssl-session-ticket
    keys:
      - dGlja2V0LW5hbWUtMDAwMUJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkI=
      - dGlja2V0LW5hbWUtMDAwMkNDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0M=
#END
--- response_body
ready [k1,k2] external false has revision nil



=== TEST 2: the local policy disables it
--- extra_yaml_config
plugin_attr:
  ssl-session-ticket:
    enabled: false
    key_source: external
--- apisix_yaml
plugin_metadata:
  - id: ssl-session-ticket
    keys:
      - dGlja2V0LW5hbWUtMDAwMUJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkI=
#END
--- response_body
empty [] external true has revision nil



=== TEST 3: generated keys are not supported in standalone mode
--- apisix_yaml
plugin_metadata:
  - id: ssl-session-ticket
    keys:
      - dGlja2V0LW5hbWUtMDAwMUJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkI=
    origin:
      source: generated
      disabled: false
#END
--- response_body
unavailable [] nil false has revision standalone mode only supports external keys
--- error_log
is unavailable: standalone mode only supports external keys



=== TEST 4: an invalid key makes the whole set unavailable
--- apisix_yaml
plugin_metadata:
  - id: ssl-session-ticket
    keys:
      - dGlja2V0LW5hbWUtMDAwMUJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkI=
      - dGlja2V0
#END
--- response_body
unavailable [] nil false has revision keys[2] must be the base64 of 80 bytes
--- error_log
is unavailable: keys[2] must be the base64 of 80 bytes
--- no_error_log
dGlja2V0LW5hbWUtMDAwMU



=== TEST 5: no record
--- apisix_yaml
routes: []
#END
--- response_body
empty [] nil nil nil nil
