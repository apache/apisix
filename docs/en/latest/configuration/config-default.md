---
title: Configuration Options
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

This page describes the configuration options defined in the `conf/config-default.yaml`.

## `apisix`

Configuration options for `apisix`.

### `admin_api_mtls`

```yaml
# Depends on `port_admin` and `https_admin`.
admin_api_mtls:

  # (string) Path of your self-signed server side cert.
  admin_ssl_cert: ""

  # (string) Path of your self-signed server side key.
  admin_ssl_cert_key: ""

  # (string) Path of your self-signed ca cert.The CA is used to sign all admin api callers' certificates.
  admin_ssl_ca_cert: ""
```

### `admin_listen`

```yaml
# The address of the admin api. Use a separate port for admin to listen on. This configuration is disabled by default.
admin_listen:

  # (ip address) Specific IP address to listen on. If not set then the server will listen on all interfaces i.e 0.0.0.0
  ip: 127.0.0.1

  # (port number) Specific port to listen on.
  port: 9180
```

### `allow_admin`

```yaml
# (ip address list) Allow admin only on specific IP addresses. If not set, then admin is allowed on all IP addresses. Put valid IP addresses only. fore more reference see: http://nginx.org/en/docs/http/ngx_http_access_module.html#allow
allow_admin:
  - 127.0.0.0/24
  # - "::/64"
```

### `config_center`

```yaml
# (string) Use config from YAML file or store config in etcd. Possible values: etcd, yaml.
config_center: etcd
```

### `control`

```yaml
# The address of the control api. Use a separate port for control to listen on. This configuration is disabled by default.
control:

  # (ip address) Specific IP address to listen on.
  ip: 127.0.0.1

  # (port number) Specific port to listen on.
  port: 9090
```

### `delete_uri_tail_slash`

```yaml
# (boolean) Enabling this will remove the trailing slash from the request URI.
delete_uri_tail_slash: false
```

### `disable_sync_configuration_during_start`

```yaml
# (boolean) Disable sync configuration during start.
disable_sync_configuration_during_start: false
```

### `dns_resolver`

```yaml
# (ip address list) The list of DNS resolvers to use. If not set, then the system default resolver will be used i.e reads from /etc/resolv.conf. This configuration is disabled by default.
dns_resolver:
  - 1.1.1.1
  - 8.8.8.8
```

### `dns_resolver_valid`

```yaml
# (integer) The number of seconds to override the TTL of valid records. If not set, then the system default TTL will be used. This configuration is disabled by default.
dns_resolver_valid: 30
```

### `enable_admin`

```yaml
# (boolean) Enable admin mode.
enable_admin: true
```

### `enable_admin_cors`

```yaml
# (boolean) Enable CORS response header for admin.
enable_admin_cors: true
```

### `enable_control`

```yaml
# (boolean) Enable control mode.
enable_control: true
```

### `enable_dev_mode`

```yaml
# (boolean) Sets nginx worker_processes to 1 when set true. This is useful for development.
enable_dev_mode: false
```

### `enable_ipv6`

```yaml
# (boolean) Enable ipv6.
enable_ipv6: true
```

### `enable_resolv_search_opt`

```yaml
# (boolean) Enables search option in resolv.conf.
enable_resolv_search_opt: true
```

### `enable_reuseport`

```yaml
# (boolean) Enables nginx SO_RESUEPORT switch if set true.
enable_reuseport: true
```

### `enable_server_tokens`

```yaml
# (boolean) Enables the APISIX version number in the server header.
enable_server_tokens: true
```

### `extra_lua_cpath`

```yaml
# (string) Load third party lua code by extending lua_package_cpath. It can override the built-in lua code.
extra_lua_cpath: ""
```

### `extra_lua_path`

```yaml
# (string) Load third party lua code by extending lua_package_path. It can override the built-in lua code.
extra_lua_path: ""
```

### `https_admin`

```yaml
# (boolean) Enables HTTPS when using a separate port for admin API. Admin API will use conf/apisix_admin_api.crt and conf/apisix_admin_api.key as HTTPS certificate and key.
https_admin: true
```

### `lua_module_hook`

```yaml
# (string) The hook module used to inject third party lua code. The format is "my_project.my_hook". This configuration is disabled by default.
lua_module_hook: ""
```

### `node_listen`

```yaml
# APISIX will listen on this port. This configuration has two forms.
# (port numbers) It can accept a list of ports if no other child configuration is set. This form is the default configuration.
node_listen:
  - 9080

# (ip, port, protocol) Or it can also accept a list of (ip address, port, protocol). This is useful when you want to specify ip address, port and protocol. This form is disabled by default.
node_listen:

  # (ip address) Specific IP address to listen on. If not set then the server will listen on all interfaces i.e 0.0.0.0
  ip: 127.0.0.2

  # (port number) Specific port to listen on.
  port: 9080

  # (boolean) Enable http2.
  http2: false
```

### `normalize_uri_like_servlet`

```yaml
# (boolean) Enables compatibility with servlet when matching the URI path.
normalize_uri_like_servlet: false
```

### `port_admin`

```yaml
# (port number) The port for the admin to listen on. This configuration is deprecated. Set this parameter using admin_listen instead.
port_admin: 9180
```

### `proxy_cache`

```yaml
# The proxy caching configuration.
proxy_cache:

  # (time) The default caching time in the disk. Uses cache time defined in the upstream by default.
  cache_ttl: 10s

  # The parameters used for setting the cache.
  zones:

      # (string) The name of the cache. Administrator can specify which cache to use by name in the admin api. Options are disk or memory.
    - name: disk_cache_one

      # (integer) The size of the shared memory to store the cache index for disk or memory strategy.
      memory_size: 50m

      # (integer) The size of the disk space dedicated to store the cache data.
      disk_size: 1G

      # (string) The absolute path of the directory to store the cache data.
      disk_path: /tmp/disk_cache_one

      # (ratio) The hierarchy level of the cache. The higher the level, the more the cache will be shared with other caches.
      cache_level: 1:2

      # Given below is the default memory cache configuration.
    - name: memory_cache
      memory_size: 50m
```

### `proxy_protocol`

```yaml
# Proxy protocol configuration. This configuration is disabled by default.
proxy_protocol:

  # (port number) The port with proxy protocol for http. Must be set to receive http request with proxy protocol. This port can only receive request with proxy protocol. Must be different from node_listen and port_admin.
  listen_http_port: 9181

  # (port number) The port with proxy protocol for https. Must be set to receive https request with proxy protocol.
  listen_https_port: 9182

  # (boolean) Enables the proxy protocol for tcp proxy, it works with stream_proxy.tcp option.
  enable_tcp_pp: true

  # (boolean) Enables the proxy protocol to the upstream server.
  enable_tcp_pp_to_upstream: true
```

### `resolver_timeout`

```yaml
# (time) The timeout for DNS resolver in seconds.
resolver_timeout: 5
```

### `show_upstream_status_in_response_header`

```yaml
# (boolean) Enables the upstream status in the response header.
show_upstream_status_in_response_header: false
```

### `ssl`

```yaml
# SSL related configuration.
ssl:

  # (boolean) Enables SSL.
  enable: true

  # (port numbers or (port, ip , protocol)) The listen configuration can be a list of ports or a list of (port, ip, protocol). It accepts a list of ports by default.
  listen:
    - 9443

    # (port, ip, protocol) It can also accept a list of (port, ip, protocol). This is useful when you want to specify ip address, port and protocol. This form is disabled by default.
      # (port number) Specific port to listen on.
    - port: 9444

      # (ip address) Specific IP address to listen on. If not set then the server will listen on all interfaces i.e 0.0.0.0
      ip: 127.0.0.3

      # (boolean) Enable http2.
      enable_http2: true

  # (boolean) Enables http2. This configuration is deprecated. Set this parameter using listen instead.
  enable_http2: true

  # (port number) The port to listen on. This configuration is deprecated. Set this parameter using listen instead.
  listen_port: 9443

  # (string) Specifies a file path with trusted CA certificate in the PEM format. This is only used to verify the certificate when APISIX needs to do SSL/TLS handshaking with external services e.g. etcd. This configuration is disabled by default.
  ssl_trusted_certificate: /path/to/ca-cert

  # (string) List of SSL protocols to be used separated by space.
  ssl_protocols: TLSv1.2 TLSv1.3

  # (string) List of SSL cipher to be used separated by hyphen.
  ssl_ciphers: ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384

  # (boolean) Enables Perfect Forward Secrecy. See here for more reference: https://github.com/mozilla/server-side-tls/issues/135
  ssl_session_tickets: false

  # (string) Encrypt SSL keys with AES-128-CBC on set. Must be of length 16. If not set, saves origin keys into etcd. CAUTION: Do not change it after saving SSL keys. It won't be able to decrypt.
  key_encrypt_salt: edd1c9f0985e76a2

  # (string) If set, when the client doesn't send SNI during handshake, this will be used instead. This configuration is disabled by default.
  fallback_sni: ""
```

### `stream_proxy`

```yaml
# TCP/UDP proxy configuration. This configuration is disabled by default.
stream_proxy:

  # (boolean) If enabled, uses stream proxy only and disables HTTP related stuffs.
  only: true

  # TCP proxy address list
  tcp:

    # (ip address:port number) Address for tcp stream proxy. Can take port number or ip address and port number combined e.g. "127.0.0.1:9101"
    addr: 9100

    # (boolean) Enables TLS on the specified port
    tls: true

  # UDP proxy address list
  udp:

    # (ip address:port number) Address for udp stream proxy. Can take port number or ip address and port number combined e.g. "127.0.0.1:9201"
    - 9200
```

## `nginx_config`

Configurations for the rendering of the template to generate `nginx.conf`.

### `enable_cpu_affinity`

```yaml
# (boolean) Enables CPU affinity. This is useful only on physical machines.
enable_cpu_affinity: true
```

### `error_log`

```yaml
# (string) The path to the error log file.
error_log: logs/error.log
```

### `error_log_level`

```yaml
# (string) The error log level. Options are: warn, error.
error_log_level: warn
```

### `envs`

```yaml
# (string) This allows to get list of specific environment variables. This configuration is disabled by default.
envs:
  - TEST_ENV
```

### `event`

```yaml
# Set number of event workers.
event:
  # (integer) The number of worker connections.
  worker_connections: 10620
```

### `http`

```yaml
# HTTP related nginx configuration.
http:

  # (boolean) Enable HTTP access log.
  enable_access_log: true

  # (string) The path to the http access log file.
  access_log: logs/access.log

  # (string) The http access log format.
  access_log_format: "$remote_addr - $remote_user [$time_local] $http_host \"$request\" $status $body_bytes_sent $request_time \"$http_referer\" \"$http_user_agent\" $upstream_addr $upstream_status $upstream_response_time \"$upstream_scheme://$upstream_host$upstream_uri\""

  # (string) Allows escaping json or default characters escaping in logs.
  access_log_format_escape: default

  # (time) Timeout for keep-alive client connection that will stay open on the server side.
  keepalive_timeout: 60s

  # (time) Timeout for reading client request header. After this 408 (Request Timeout) response will be sent to the client.
  client_header_timeout: 60s

  # (time) Timeout for reading client request body. After this 408 (Request Timeout) response will be sent to the client.
  client_body_timeout: 60s

  # (integer) the maximum allowed size of client request body.
  client_max_body_size: 0

  # (time) Timeout for transmitting a response to the client before closing the connection.
  send_timeout: 10s

  # (string) Enable the use of underscores in client request header field names.
  underscores_in_headers: "on"

  # (string) Defines the request header field whose value will be used to replace the client address. See here: http://nginx.org/en/docs/http/ngx_http_realip_module.html#real_ip_header
  real_ip_header: X-Real-IP

  # (string) If recursive search is disabled, the original client address that matches one of the trusted addresses is replaced by the last address sent in the request header field defined by the real_ip_header directive. If recursive search is enabled, the original client address that matches one of the trusted addresses is replaced by the last non-trusted address sent in the request header field. See here: http://nginx.org/en/docs/http/ngx_http_realip_module.html#real_ip_recursive
  real_ip_recursive: "off"

  # (string) Defines trusted addresses that are known to send correct replacement addresses. If the special value unix: is specified, all UNIX-domain sockets will be trusted. Trusted addresses may also be specified using a hostname. See here: http://nginx.org/en/docs/http/ngx_http_realip_module.html#set_real_ip_from
  set_real_ip_from:
    - 127.0.0.1
    - "unix:"

  # Add custom shared cache to nginx.conf. Set the cache as "cache-key: cache-size". This configuration is disabled by default.
  custom_lua_shared_dict:

    # (integer) The size of the ipc shared dictionary.
    ipc_shared_dict: 100m

  # (boolean) Enables passing of the server name through TLS Server Name Indication extension (SNI, RFC 6066) when establishing a connection with the proxied HTTPS server.
  proxy_ssl_server_name: true

  # Upstream related configuration
  upstream:

    # (string) The upstream type. Options are: http, tcp, udp.
    type: http

    # (integer) The maximum number of idle keep-alive connections to the upstream server that are preserved in the cache of each worker process. If the number of connections exceeds this value, the least recently used connections will be closed.
    keepalive: 320

    # (integer) The maximum number of request that can be served through one keep-alive connection. If the number of requests exceeds this value, the connection will be closed.
    keepalive_requests: 1000

    # (integer) Timeout for closing an idle keep-alive connection to the upstream server.
    keepalive_timeout: 60s

  # (string) Adds the specified charset to the Content-Type response header field. See here: http://nginx.org/en/docs/http/ngx_http_charset_module.html#charset
  charset: utf-8

  # (integer) The maximum size of the variable hash table.
  variables_hash_max_size: 2048

  # Lua shared dict configuration
  lua_shared_dict:
    internal-status: 10m
    plugin-limit-req: 10m
    plugin-limit-count: 10m
    prometheus-metrics: 10m
    plugin-limit-conn: 10m
    upstream-healthcheck: 10m
    worker-events: 10m
    lrucache-lock: 10m
    balancer-ewma: 10m
    balancer-ewma-locks: 10m
    balancer-ewma-last-touched-at: 10m
    plugin-limit-count-redis-cluster-slot-lock: 1m
    tracing_buffer: 10m
    plugin-api-breaker: 10m
    etcd-cluster-health-check: 10m
    discovery: 1m
    jwks: 1m
    introspection: 10m
    access-tokens: 1m
    ext-plugin: 1m
    kubernetes: 1m
    tars: 1m
```

### `http_admin_configuration_snippet`

```yaml
# Add well indented custom Nginx admin server configuration. Please check for conflicts with APISIX snippets.
http_admin_configuration_snippet: |
  # Add custom Nginx admin server configuration to nginx.conf.
  # The configuration should be well indented!
```

### `http_configuration_snippet`

```yaml
# Add well indented custom Nginx http configuration. Please check for conflicts with APISIX snippets.
http_configuration_snippet: |
  # Add custom Nginx http configuration to nginx.conf.
  # The configuration should be well indented!
```

### `http_end_configuration_snippet`

```yaml
# Add well indented custom Nginx http end configuration. Please check for conflicts with APISIX snippets.
http_end_configuration_snippet: |
  # Add custom Nginx http end configuration to nginx.conf.
  # The configuration should be well indented!
```

### `http_server_configuration_snippet`

```yaml
# Add well indented custom Nginx http server configuration. Please check for conflicts with APISIX snippets.
http_server_configuration_snippet: |
  # Add custom Nginx http server configuration to nginx.conf.
  # The configuration should be well indented!
```

### `http_server_location_configuration_snippet`

```yaml
# Add well indented custom Nginx http server location configuration. Please check for conflicts with APISIX snippets.
http_server_location_configuration_snippet: |
  # Add custom Nginx http server location configuration to nginx.conf.
  # The configuration should be well indented!
```

### `main_configuration_snippet`

```yaml
# Add well indented custom Nginx main configuration. Please check for conflicts with APISIX snippets.
main_configuration_snippet: |
  # Add custom Nginx main configuration to nginx.conf.
  # The configuration should be well indented!
```

### `max_pending_timers`

```yaml
# (integer) The maximum number of pending timers. Increase this number if you are getting "too many pending timers" error.
max_pending_timers: 16384
```

### `max_running_timers`

```yaml
# (integer) The maximum number of running timers. Increase this number if you are getting "lua_max_running_timers are not enough" error.
max_running_timers: 4096
```

### `meta`

```yaml
meta:
  lua_shared_dict:
    prometheus-metrics: 15m
```

### `stream`

```yaml
# Stream related configurations
stream:

  # (boolean) Enable access to logs
  enable_access_log: false

  # (string) The path to store stream access log
  access_log: logs/access_stream.log

  # (string) The format for the stream access log. Create your custom log format here: http://nginx.org/en/docs/varindex.html
  access_log_format: "$remote_addr [$time_local] $protocol $status $bytes_sent $bytes_received $session_time"

  # (string) Allows escaping json or default characters escaping in logs
  access_log_format_escape: default

  # Lua shared dict configuration.
  lua_shared_dict:

    # (time) Interval to check health of etcd cluster.
    etcd-cluster-health-check-stream: 10m

    # (time) Time to lock LRU cache.
    lrucache-lock-stream: 10m

    # (time) Time to limit plugin connection.
    plugin-limit-conn-stream: 10m
```

### `stream_configuration_snippet`

```yaml
# Add well indented custom Nginx stream configuration. Please check for conflicts with APISIX snippets.
stream_configuration_snippet: |
  # Add custom Nginx stream configuration to nginx.conf.
  # The configuration should be well indented!
```

### `user`

```yaml
# (string) This configuration specifies the execution user of the worker process. This is only useful if the master process runs with super-user privileges. This configuration is disabled by default.
user: root
```

### `worker_processes`

```yaml
# (auto) This configuration enables use of multiple cores in container. The exact number of CPU cores can be set by setting "APISIX_WORKER_PROCESSES" environment variable.
worker_processes: auto
```

### `worker_rlimit_nofile`

```yaml
# (integer) The maximum number of open files per worker process. This should be larger than number of worker_connections.
worker_rlimit_nofile: 20480
```

### `worker_shutdown_timeout`

```yaml
# (time) The timeout for graceful worker shutdown of the worker process.
worker_shutdown_timeout: 240s
```

## `etcd`

### `health_check_retry`

```yaml
# (integer) The number of retries by etcd for health check.
health_check_retry: 2
```

### `health_check_timeout`

```yaml
# (time) The etcd will retry unhealthy nodes after this interval in seconds. This configuration is disabled by default.
health_check_timeout: 10
```

### `host`

```yaml
# (etcd addresses) The etcd host address. It is possible to specify multiple addresses of the same etcd cluster as a list of strings. If your etcd cluster enables TLS, you should use the https scheme e.g. Https://127.0.0.1:2379.
host:
  - "http://127.0.0.1:2379"
```

### `password`

```yaml
# (string) The root password for etcd. This configuration is disabled by default.
password: 5tHkHhYkjr6cQY
```

### `prefix`

```yaml
# (string) APISIX configuration prefix
prefix: /apisix
```

### `resync_delay`

```yaml
# (time) Time to rest when sync failed. Resync will be attempted after this interval plus 50% random jitter. This configuration is disabled by default.
resync_delay: 5
```

### `timeout`

```yaml
# (time) The timeout for etcd client in seconds.
timeout: 30
```

### `tls`

```yaml
# To enable etcd client certificate you need to build APISIX-Base, see here: https://apisix.apache.org/docs/apisix/FAQ#how-do-i-build-the-apisix-base-environment?
tls:

  # (string) The path to the certificate file used by the etcd client. This configuration is disabled by default.
  cert: /path/to/cert.pem

  # (string) The path to the private key file used by the etcd client. This configuration is disabled by default.
  key: /path/to/key.pem

  # (boolean) Verify the etcd endpoint certificate when setting up a TLS connection.
  verify: true

  # (string) The SNI for etcd TLS requests. If not set, the host part of the URL will be used. This configuration is disabled by default.
  sni:
```

### `user`

```yaml
# (string) The root user name for etcd client. This configuration is disabled by default.
user: root
```

## `vault`

HashiCorp Vault storage backend for sensitive data retrieval. The config shows an example of what APISIX expects if you wish to integrate Vault for secret (sensetive string, public private keys etc.) retrieval. APISIX communicates with Vault server HTTP APIs. By default, APISIX doesn't need this configuration.

```yaml
# This configuration enables Vault integration and is disabled by default.
vault:

  # (string) The host address where Vault server is running.
  host: "http://0.0.0.0:8200"

  # (time) The request timeout for Vault client in seconds.
  timeout: 10

  # (string) Authentication token for Vault client.
  token: root

  # (string) APISIX supports vault kv engine v1, where sensitive data are being stored and retrieved through vault HTTP APIs. enabling a prefix allows you to better enforcement of policies, generate limited scoped tokens and tightly control the data that can be accessed from APISIX.
  prefix: kv/apisix
```

## `discovery`

Configuration for service discovery center. This whole configuration is disabled by default.

```yaml
# DNS configuration for service discovery.
dns:

  # (string) The DNS server address. Use the real address.
  server:
    - "http://127.0.0.1:8761"

eureka:

  # (strings) The eureka host address. It is possible to specify multiple addresses of the same eureka cluster as a list of strings.
  host:
    - "http://127.0.0.1:8761"

  # (string) Prefix for the eureka server.
  prefix: /eureka/

  # (time) The fetch interval for eureka server.
  fetch_interval: 30

  # (integer) The weight for the node. The weight is used to determine the node's priority when choosing the node to serve the request.
  weight: 100

  # Timeout configuration for eureka server in milliseconds.
  timeout:
    connect: 2000
    read: 5000
    send: 2000
```

## `graphql`

GraphQL configuration.

```yaml
graphql:
  # (integer) The maximum size of graphql in bytes. The default value is 1048576 (1MiB).
  max_size: 1048576
```

## `plugin_attr`

`plugin_attr` is a configuration for APISIX plugins. These settings can be used to set plugin specific attributes.

### `log_rotate`

```yaml
log-rotate:

  # (time) Rotate interval in seconds.
  interval: 3600

  # (integer) The maximum number of log file to be kept.
  max_kept: 168

  # (boolean) Enables log file compression(gzip).
  enable_compression: true
```

### `skywalking`

```yaml
skywalking:

  # (string) The name of the service.
  service_name: APISIX

  # (string) The service instance name.
  service_instance_name: APISIX Instance Name

  # (string) The service instance endpoint address.
  endpoint_addr: http://127.0.01:12800
```

### `opentelemetry`

```yaml
# OpenTelemetry configuration.
opentelemetry:

  # (string) Trace ID source.
  trace_id_source: x-request-id

  resource:
    # (string) Name of the service.
    service.name: APISIX

  collector:
    # (string) The collector address.
    address: 127.0.0.1:4318

    # (time) The collector timeout in seconds.
    request_timeout: 3

    # The collector request headers.
    request_headers:

      # (string) The authorization header.
      Authorization: token

    batch_span_processor:

      # (boolean) If set drop spans if the queue is full.
      drop_on_queue_full: false

      # (integer) The maximum size of the queue.
      max_queue_size: 1024

      # (time) Timeout for the batch span processor.
      batch_timeout: 2

      # (time) Timeout for inactive spans.
      inactive_timeout: 1

      # (integer) Maximum batch size of export.
      max_export_batch_size: 16
```

### `prometheus`

```yaml
prometheus:

  # (string) Export URI for prometheus.
  export_uri: /apisix/prometheus/metrics

  # (string) Prefix for the prometheus metrics.
  metric_prefix: apisix_

  # (boolean) Enable prometheus export server.
  enable_export_server: true

  # (ip address, port number) The prometheus export server address.
  export_addr:
    ip: 127.0.0.1
    port: 9091
```

### `server-info`

```yaml
server-info:
  # (time) Time to live in seconds for the server info in etcd.
  report_ttl: 60
```

### `dubbo-proxy`

```yaml
dubbo-proxy:
  # (integer) Number of upstream multiplex connections.
  upstream_multiplex_count: 32
```

### `request-id`

```yaml
request-id:
  snowflake:

    # (boolean) Enable snowflake.
    enable: false

    # (integer) The starting timestamp of the snowflake in milliseconds.
    snowflake_epoc: 1609459200000

    # (integer) Number of data machine bits. The maximum is 31, because Lua cannot do bitwise operation on more than 31 bits.
    data_machine_bits: 12

    # (integer) The number sequence bits. Each machine generates a maximum of (1 << sequence_bits) serial numbers per millisecond.
    sequence_bits: 10

    # (time) Time to live in seconds for data_machine in etcd.
    data_machine_ttl: 30

    # (time) The time interval for lease renewal in seconds in etcd.
    data_machine_interval: 10
```

### `proxy-mirror`

```yaml
proxy-mirror:

  # Timeout for the proxy mirror in seconds.
  timeout:
    connect: 60s
    read: 60s
    send: 60s
```

### `redirect`

```yaml
redirect:
  # (port number) The default port to be used by HTTP redirect to HTTPS. This configuration is disabled by default.
  https_port: 8443
```

## `wasm`

Configuration for WASM module. This whole configuration is disabled by default.

```yaml
wasm:
  plugins:

      # (string) Name of the WASM plugin.
    - name: wasm_log

      # (integer) Priority of the WASM plugin.
      priority: 7999\

      # (string) Path to the WASM plugin.
      file: t/wasm/log/main.go.wasm
```

## `plugins`

The list of plugins sorted by priority.

```yaml
# (strings) Name of the plugin. The whole list can be found in the conf/config-default.yaml.
plugins:
  - plugin-with-priority-1
  ...
  - plugin-with-priority-N
```

## `stream_plugin`

The list of stream plugins sorted by priority.

```yaml
# (strings) Name of the stream plugin. The whole list can be found in the conf/config-default.yaml.
stream_plugins:
  - plugin-with-priority-1
  ...
  - plugin-with-priority-N
```

## `ext-plugin`

External plugins. Specify the command to be executed. This configuration is disabled by default.

```yaml
ext-plugin:
  # (command parameters as array) The command to be executed.
  cmd: ["ls", "-l"]
```

## `xrpc`

XRPC configuration. This configuration is disabled by default.

```yaml

```yaml
xrpc:
  # XRPC protocols.
  - name: pingpong
```
