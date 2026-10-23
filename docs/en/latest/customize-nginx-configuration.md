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

The Nginx configuration used by APISIX is generated via the template file `apisix/cli/ngx_tpl.lua` and the parameters in `apisix/cli/config.lua` and `conf/config.yaml`.

You can take a look at the generated Nginx configuration in `conf/nginx.conf` after running `./bin/apisix start`.

If you want to customize the Nginx configuration, please read through the `nginx_config` in `conf/config.default.example`. You can override the default value in the `conf/config.yaml`. For instance, you can inject some snippets in the `conf/nginx.conf` via configuring the `xxx_snippet` entries:

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

Pay attention to the indent of `nginx_config` and sub indent of the sub entries, the incorrect indent may cause `./bin/apisix start` to fail to generate Nginx configuration in `conf/nginx.conf`.

## IPv6 Listeners

When `apisix.enable_ipv6` is `true` (the default), APISIX adds IPv6 listeners
for enabled Admin API, Control API, status, and Prometheus export servers that
use their default IP addresses. The Admin API listens on `[::]` in addition to
`0.0.0.0`; the other servers listen on `[::1]` in addition to `127.0.0.1`, keeping
them restricted to loopback. Both listeners use the configured port and the
same options, including TLS for the Admin API.

Setting an IP different from the server's default keeps only that configured
address. Setting `apisix.enable_ipv6` to `false` disables the automatically
added IPv6 listeners; it does not remove an explicitly configured IPv6 address.
Admin API access restrictions such as `deployment.admin.allow_admin` still
apply to IPv6 requests. If you previously added equivalent IPv6 listeners via
configuration snippets, remove those snippets to avoid duplicate listeners.
