---
title: Customize Nginx configuration
---

<!--
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
-->

The Nginx configuration used by APISIX is generated via the template file `apisix/cli/ngx_tpl.lua` and the options from `conf/config-default.yaml` / `conf/config.yaml`.

You can take a look at the generated Nginx configuration in `conf/nginx.conf` after running `./bin/apisix start`.

If you want to customize the Nginx configuration, please read through the `nginx_config` in `conf/config-default.yaml`. You can override the default value in the `conf/config.yaml`. For instance, you can custum access_log_format via configuring the `http` entries; you can inject some snippets in the `conf/nginx.conf` via configuring the `xxx_snippet` entries:

```yaml
...
# put this in config.yaml:
nginx_config:
  http:
    access_log: logs/access.log
    access_log_format_escape: json      #override the access_log_format_escape value from `default` to `json`, together with curresponding configuration of access_log_format 
    access_log_format: '{"time":"$time_iso8601","host":"$hostname","server_ip":"$server_addr","client_ip":"$remote_addr"}'
  main_configuration_snippet: |
    daemon on;
  http_configuration_snippet: |
    log_format  server-log-format       #custom a server-log-format for server log
    '{"@timestamp":"$time_iso8601",'
    '"host":"$hostname",'
    '"server_ip":"$server_addr",'
    '"client_ip":"$remote_addr",'
    '"xff":"$http_x_forwarded_for",'
    '"domain":"$host",'
    '"url":"$uri",'
    '"referer":"$http_referer",'
    '"args":"$args",'
    '"upstreamtime":"$upstream_response_time",'
    '"responsetime":"$request_time",'
    '"request_method":"$request_method",'
    '"status":"$status",'
    '"size":"$body_bytes_sent",'
    '"request_body":"$request_body",'
    '"request_length":"$request_length",'
    '"protocol":"$server_protocol",'
    '"upstreamhost":"$upstream_addr",'
    '"file_dir":"$uri",'
    '"http_user_agent":"$http_user_agent"'
    '}';

    server
    {
      listen 45651;
      server_name _;
      access_log off;

      location /ysec_status {
        req_status_show;
        allow 127.0.0.1;
        deny all;
      }
    }

    server
    {
      listen 45652;
      server_name 127.0.0.1;
      access_log logs/server/access.log server-log-format;

      location / {
        # some normal configurations
        #
      }
    }

    chunked_transfer_encoding on;

  http_server_configuration_snippet: |
    set $my "var";
  http_admin_configuration_snippet: |
    log_format admin "$request_time $pipe";
  http_end_configuration_snippet: |
    server_names_hash_bucket_size 128;
  stream_configuration_snippet: |
    tcp_nodelay off;
...
```

Pay attention to the indent of `nginx_config` and sub indent of the sub entries, the incorrect indent may cause `./bin/apisix start` failed to generate Nginx configuration in `conf/nginx.conf`.
