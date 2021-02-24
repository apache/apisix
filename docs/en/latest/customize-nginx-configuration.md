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

# Customize Nginx configuration

The Nginx configuration used by APISIX is generated via the template file `apisix/ngx_tpl.lua` and the options from `conf/config-default.yaml` / `conf/config.yaml`.

You can take a look at the generated Nginx configuration in `conf/nginx.conf` after running `./bin/apisix start`.

If you want to customize the Nginx configuration, please read through the `nginx_config` in `conf/config-default.yaml`. You can override the default value in the `conf/config.yaml`. For instance, you can inject some snippets in the `conf/nginx.conf` via configuring the `xxx_snippet` entries:

```yaml
...
# put this in config.yaml:
nginx_config:
    main_configuration_snippet: |
        daemon on;
    http_configuration_snippet: |
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
