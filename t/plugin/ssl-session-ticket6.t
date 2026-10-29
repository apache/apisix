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

# the runtime takes over the session ticket keys of the business TLS listeners
my $takeover = 0;
if ($version =~ m/--prefix=(\S+)\/nginx/) {
    $takeover = -f "$1/lualib/resty/apisix/ssl_session_ticket.lua";
}

if (!$takeover) {
    plan(skip_all => "the runtime does not take over the session ticket keys");
} elsif ($version !~ m/--with-debug/) {
    plan(skip_all => "the failure is only injected in a debug build of the runtime");
} else {
    plan('no_plan');
}

# every registration of the ticket key callback fails, as if OpenSSL refused
# it: read by the master when it loads the configuration
$ENV{APISIX_TEST_SSL_SESSION_TICKET_REGISTER_FAIL} = 1;

repeat_each(1);
no_long_string();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!defined $block->yaml_config) {
        $block->set_value("yaml_config", <<_EOC_);
apisix:
  id: ssl-session-ticket-test
  node_listen: 1984
  proxy_mode: http&stream
  stream_proxy:
    tcp:
      - 9100
  enable_resolv_search_opt: false
deployment:
  role: traditional
  role_traditional:
    config_provider: etcd
  admin:
    admin_key: null
plugin_attr:
  ssl-session-ticket:
    enabled: true
    key_source: external
_EOC_
    }

    my $config = $block->config // "";
    $block->set_value("config", $config . <<_EOC_);
    location = /reused {
        content_by_lua_block {
            require("lib.ssl_session_ticket").respond()
        }
    }
_EOC_

    if (!defined $block->stream_server_config) {
        $block->set_value("stream_server_config", <<_EOC_);
    listen 2005 ssl;
    ssl_certificate             cert/apisix.crt;
    ssl_certificate_key         cert/apisix.key;
    ssl_session_tickets off;
    apisix_ssl_session_ticket_takeover on;

    ssl_client_hello_by_lua_block {
        apisix.ssl_client_hello_phase()
    }

    ssl_certificate_by_lua_block {
        apisix.ssl_phase()
    }

    content_by_lua_block {
        local sock = ngx.req.socket()
        sock:receive()
        require("lib.ssl_session_ticket").respond()
    }
_EOC_
    }
    $block->set_value("stream_conf_enable", 1);
});

run_tests;

__DATA__

=== TEST 1: a context whose callback is not registered stays off, and the node says so
--- config
    location /t {
        lua_ssl_protocols TLSv1.2;
        content_by_lua_block {
            local h = require("lib.ssl_session_ticket")
            local json = require("toolkit.json")
            h.set_ssl()
            h.put_keys(1)
            local st = h.wait_status(function(st)
                return st.version and st.key_count == 1
                       and st.reason == "module_not_active"
                       and st.subsystems.stream.reason == "module_not_active"
            end)
            ngx.say(st.status, " ", st.reason, " ", st.key_count, " ", st.effective_key_count,
                    " ", st.fully_applied, " ", st.last_apply_error)
            ngx.say("workers: ", json.encode(st.workers))
            for _, name in ipairs({"http", "stream"}) do
                local sub = st.subsystems[name]
                ngx.say(name, ": ", sub.applicable, " ", sub.status, " ", sub.reason, " ",
                        sub.contexts)
            end
            for _, l in ipairs({{"https", 1994, true}, {"stream", 2005}}) do
                local r = assert(h.connect(l[2], {http = l[3]}))
                ngx.say(l[1], ": tickets=", r.tickets, " ticket=", r.ticket)
            end
            local ctx = require("resty.apisix.ssl_session_ticket").contexts()[1]
            ngx.say("context: registered=", ctx.registered, " tickets=", ctx.tickets,
                    " keys=", ctx.keys)
        }
    }
--- response_body
degraded module_not_active 1 nil false context 1: not_registered
workers: {"applied":0,"failed":1,"pending":0,"total":1}
http: true degraded module_not_active 1
stream: true degraded module_not_active 1
https: tickets=off ticket=nil
stream: tickets=off ticket=nil
context: registered=false tickets=false keys=0
--- error_log
failed to apply the TLS session ticket keys: context 1: not_registered
--- timeout: 15
