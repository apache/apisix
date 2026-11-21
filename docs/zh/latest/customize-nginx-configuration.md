---
title: 自定义 Nginx 配置
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

APISIX 使用的 Nginx 配置是通过模板文件 `apisix/cli/ngx_tpl.lua` 以及 `apisix/cli/config.lua` 和`conf/config.yaml` 中的参数生成的。

在执行完 `./bin/apisix start`，你可以在 `conf/nginx.conf` 看到生成的 Nginx 配置文件。

如果你需要自定义 Nginx 配置，请阅读 `conf/config.default.example` 中的 `nginx_config`。你可以在 `conf/config.yaml` 中覆盖默认值。例如，你可以在 `conf/nginx.conf` 中通过配置 `xxx_snippet` 条目注入一些代码片段：

```yaml
...
# config.yaml 里面的内容
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

注意`nginx_config`及其子项的格式缩进，在执行`./bin/apisix start`时，错误的缩进将导致更新`conf/nginx.conf`文件失败。

## IPv6 监听地址

当 `apisix.enable_ipv6` 为 `true`（默认值）时，APISIX 会为使用默认 IP 地址的已启用
Admin API、Control API、状态服务和 Prometheus 指标导出服务添加 IPv6 监听地址。
Admin API 在 `0.0.0.0` 之外还会监听 `[::]`；其他服务在 `127.0.0.1` 之外还会监听
`[::1]`，确保这些服务仍然只能通过回环地址访问。两种地址使用相同的配置端口和监听选项，
包括 Admin API 的 TLS 配置。

如果配置的 IP 与该服务的默认 IP 不同，则仅监听配置的地址。将 `apisix.enable_ipv6`
设为 `false` 会禁用自动添加的 IPv6 监听地址，但不会移除显式配置的 IPv6 地址。
`deployment.admin.allow_admin` 等 Admin API 访问限制仍然适用于 IPv6 请求。
如果之前通过配置片段添加了相同的 IPv6 监听地址，请移除这些片段，避免重复监听。
