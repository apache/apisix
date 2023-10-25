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

plan('no_plan');

repeat_each(1);
log_level('warn');
no_root_location();
no_shuffle();
workers(4);

add_block_preprocessor(sub {
    my ($block) = @_;

    my $yaml_config = <<_EOC_;
apisix:
  node_listen: 1984
  enable_admin: false
deployment:
    role: data_plane
    role_data_plane:
        config_provider: yaml
discovery:
  tars:
    db_conf:
      host: 127.0.0.1
      port: 3306
      database: db_tars
      user: root
      password: tars2022
    full_fetch_interval: 3
    incremental_fetch_interval: 1
_EOC_

    $block->set_value("yaml_config", $yaml_config);

    my $apisix_yaml = $block->apisix_yaml // <<_EOC_;
routes: []
#END
_EOC_

    $block->set_value("apisix_yaml", $apisix_yaml);

    my $extra_init_by_lua_start = <<_EOC_;
        -- reduce incremental_fetch_interval,full_fetch_interval
        local schema = require("apisix.discovery.tars.schema")
        schema.properties.incremental_fetch_interval.minimum=1
        schema.properties.incremental_fetch_interval.default=1
        schema.properties.full_fetch_interval.minimum = 3
        schema.properties.full_fetch_interval.default = 3
_EOC_

    $block->set_value("extra_init_by_lua_start", $extra_init_by_lua_start);
    $block->set_value("stream_extra_init_by_lua_start", $extra_init_by_lua_start);

    my $config = $block->config // <<_EOC_;

        location /sql {
            content_by_lua_block {
                local mysql = require("resty.mysql")
                local core = require("apisix.core")
                local ipairs = ipairs

                ngx.req.read_body()
                local sql = ngx.req.get_body_data()
                core.log.info("get sql ", sql)

                local db_conf= {
                  host="127.0.0.1",
                  port=3306,
                  database="db_tars",
                  user="root",
                  password="tars2022",
                }

                local db_cli, err = mysql:new()
                if not db_cli then
                  core.log.error("failed to instantiate mysql: ", err)
                  return
                end
                db_cli:set_timeout(3000)

                local ok, err, errcode, sqlstate = db_cli:connect(db_conf)
                if not ok then
                  core.log.error("failed to connect mysql: ", err, ", ", errcode, ", ", sqlstate)
                  return
                end

                local res, err, errcode, sqlstate = db_cli:query(sql)
                if not res then
                   ngx.say("bad result: ", err, ": ", errcode, ": ", sqlstate, ".")
                   return
                end
                ngx.say("DONE")
            }
        }
_EOC_

    $block->set_value("config", $config);

    my $stream_config = $block->stream_config // <<_EOC_;
        server {
            listen 8125;
            content_by_lua_block {
                local core = require("apisix.core")
                local d = require("apisix.discovery.tars")

                ngx.sleep(2)

                local sock = ngx.req.socket()
                local request_body = sock:receive()

                core.log.info("get body ", request_body)

                local response_body = "{"
                local queries = core.json.decode(request_body)
                for _,query in ipairs(queries) do
                  local nodes = d.nodes(query)
                  if nodes==nil or #nodes==0 then
                      response_body=response_body.." "..0
                  else
                      response_body=response_body.." "..#nodes
                  end
                end
                ngx.say(response_body.." }")
            }
        }

_EOC_

    $block->set_value("extra_stream_config", $stream_config);

});

run_tests();

__DATA__

=== TEST 1: create initial server and servant
--- timeout: 3
--- request eval
[
"POST /sql
truncate table t_server_conf",

"POST /sql
truncate table t_adapter_conf",

"POST /sql
insert into t_server_conf(application, server_name, node_name, registry_timestamp,
                          template_name, setting_state, present_state, server_type)
values ('A', 'AServer', '172.16.1.1', now(), 'taf-cpp', 'active', 'active', 'tars_cpp'),
       ('B', 'BServer', '172.16.2.1', now(), 'taf-cpp', 'active', 'active', 'tars_cpp'),
       ('C', 'CServer', '172.16.3.1', now(), 'taf-cpp', 'active', 'active', 'tars_cpp')",

"POST /sql
insert into t_adapter_conf(application, server_name, node_name, adapter_name, endpoint, servant)
values ('A', 'AServer', '172.16.1.1', 'A.AServer.FirstObjAdapter',
        'tcp -h 172.16.1.1 -p 10001 -e 0 -t 6000', 'A.AServer.FirstObj'),
       ('B', 'BServer', '172.16.2.1', 'B.BServer.FirstObjAdapter',
        'tcp -p 10001 -h 172.16.2.1 -e 0 -t 6000', 'B.BServer.FirstObj'),
       ('C', 'CServer', '172.16.3.1', 'C.CServer.FirstObjAdapter',
        'tcp -e 0 -h 172.16.3.1 -t 6000 -p 10001 ', 'C.CServer.FirstObj')",

]
--- response_body eval
[
    "DONE\n",
    "DONE\n",
    "DONE\n",
    "DONE\n",
]



=== TEST 2: get count after create servant
--- apisix_yaml
stream_routes:
  -
    id: 1
    server_port: 1985
    upstream_id: 1

upstreams:
  - nodes:
      "127.0.0.1:8125": 1
    type: roundrobin
    id: 1

#END
--- stream_request
["A.AServer.FirstObj","B.BServer.FirstObj", "C.CServer.FirstObj"]
--- stream_response eval
qr{ 1 1 1 }
