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

local table_conact = table.concat

local _M = {
  apisix = {
    node_listen = { 9080 },
    enable_admin = true,
    enable_dev_mode = false,
    enable_reuseport = true,
    show_upstream_status_in_response_header = false,
    enable_ipv6 = true,
    enable_http2 = true,
    enable_server_tokens = true,
    extra_lua_path = "",
    extra_lua_cpath = "",
    proxy_cache = {
      cache_ttl = "10s",
      zones = {
        {
          name = "disk_cache_one",
          memory_size = "50m",
          disk_size = "1G",
          disk_path = "/tmp/disk_cache_one",
          cache_levels = "1:2"
        },
        {
          name = "memory_cache",
          memory_size = "50m"
        }
      }
    },
    delete_uri_tail_slash = false,
    normalize_uri_like_servlet = false,
    router = {
      http = "radixtree_host_uri",
      ssl = "radixtree_sni"
    },
    proxy_mode = "http",
    resolver_timeout = 5,
    enable_resolv_search_opt = true,
    ssl = {
      enable = true,
      listen = { {
        port = 9443,
        enable_http3 = false
      } },
      ssl_protocols = "TLSv1.2 TLSv1.3",
      ssl_ciphers = table_conact({
        "ECDHE-ECDSA-AES128-GCM-SHA256", "ECDHE-RSA-AES128-GCM-SHA256",
        "ECDHE-ECDSA-AES256-GCM-SHA384", "ECDHE-RSA-AES256-GCM-SHA384",
        "ECDHE-ECDSA-CHACHA20-POLY1305", "ECDHE-RSA-CHACHA20-POLY1305",
        "DHE-RSA-AES128-GCM-SHA256", "DHE-RSA-AES256-GCM-SHA384",
      }, ":"),
      ssl_session_tickets = false,
      ssl_trusted_certificate = "system"
    },
    enable_control = true,
    disable_sync_configuration_during_start = false,
    data_encryption = {
      enable_encrypt_fields = true,
      keyring = { "qeddd145sfvddff3", "edd1c9f0985e76a2" }
    },
    events = {
      module = "lua-resty-events"
    }
  },
  nginx_config = {
    error_log = "logs/error.log",
    error_log_level = "warn",
    worker_processes = "auto",
    enable_cpu_affinity = false,
    worker_rlimit_nofile = 20480,
    worker_shutdown_timeout = "240s",
    max_pending_timers = 16384,
    max_running_timers = 4096,
    event = {
      worker_connections = 10620
    },
    meta = {
      lua_shared_dict = {
        ["prometheus-metrics"] = "15m"
      }
    },
    stream = {
      enable_access_log = false,
      access_log = "logs/access_stream.log",
      -- luacheck: push max code line length 300
      access_log_format = "$remote_addr [$time_local] $protocol $status $bytes_sent $bytes_received $session_time",
      -- luacheck: pop
      access_log_format_escape = "default",
      lua_shared_dict = {
        ["etcd-cluster-health-check-stream"] = "10m",
        ["lrucache-lock-stream"] = "10m",
        ["plugin-limit-conn-stream"] = "10m",
        ["worker-events-stream"] = "10m",
        ["tars-stream"] = "1m"
      }
    },
    main_configuration_snippet = "",
    http_configuration_snippet = "",
    http_server_configuration_snippet = "",
    http_server_location_configuration_snippet = "",
    http_admin_configuration_snippet = "",
    http_end_configuration_snippet = "",
    stream_configuration_snippet = "",
    http = {
      enable_access_log = true,
      access_log = "logs/access.log",
      access_log_buffer = 16384,
      -- luacheck: push max code line length 300
      access_log_format =
      '$remote_addr - $remote_user [$time_local] $http_host "$request" $status $body_bytes_sent $request_time "$http_referer" "$http_user_agent" $upstream_addr $upstream_status $upstream_response_time "$upstream_scheme://$upstream_host$upstream_uri"',
      -- luacheck: pop
      access_log_format_escape = "default",
      keepalive_timeout = "60s",
      client_header_timeout = "60s",
      client_body_timeout = "60s",
      client_max_body_size = 0,
      send_timeout = "10s",
      underscores_in_headers = "on",
      real_ip_header = "X-Real-IP",
      real_ip_recursive = "off",
      real_ip_from = { "127.0.0.1", "unix:" },
      proxy_ssl_server_name = true,
      upstream = {
        keepalive = 320,
        keepalive_requests = 1000,
        keepalive_timeout = "60s"
      },
      charset = "utf-8",
      variables_hash_max_size = 2048,
      lua_shared_dict = {
        ["internal-status"] = "10m",
        ["plugin-limit-req"] = "10m",
        ["plugin-limit-count"] = "10m",
        ["prometheus-metrics"] = "10m",
        ["plugin-limit-conn"] = "10m",
        ["upstream-healthcheck"] = "10m",
        ["worker-events"] = "10m",
        ["lrucache-lock"] = "10m",
        ["balancer-ewma"] = "10m",
        ["balancer-ewma-locks"] = "10m",
        ["balancer-ewma-last-touched-at"] = "10m",
        ["plugin-limit-req-redis-cluster-slot-lock"] = "1m",
        ["plugin-limit-count-redis-cluster-slot-lock"] = "1m",
        ["plugin-limit-conn-redis-cluster-slot-lock"] = "1m",
        tracing_buffer = "10m",
        ["plugin-api-breaker"] = "10m",
        ["etcd-cluster-health-check"] = "10m",
        discovery = "1m",
        jwks = "1m",
        introspection = "10m",
        ["access-tokens"] = "1m",
        ["ext-plugin"] = "1m",
        tars = "1m",
        ["cas-auth"] = "10m",
        ["ocsp-stapling"] = "10m"
      }
    }
  },
  graphql = {
    max_size = 1048576
  },
  plugins = {
    "real-ip",
    "ai",
    "client-control",
    "proxy-control",
    "request-id",
    "zipkin",
    "ext-plugin-pre-req",
    "fault-injection",
    "mocking",
    "serverless-pre-function",
    "cors",
    "ip-restriction",
    "ua-restriction",
    "referer-restriction",
    "csrf",
    "uri-blocker",
    "request-validation",
    "chaitin-waf",
    "multi-auth",
    "openid-connect",
    "cas-auth",
    "authz-casbin",
    "authz-casdoor",
    "wolf-rbac",
    "ldap-auth",
    "hmac-auth",
    "basic-auth",
    "jwt-auth",
    "jwe-decrypt",
    "key-auth",
    "consumer-restriction",
    "attach-consumer-label",
    "forward-auth",
    "opa",
    "authz-keycloak",
    "proxy-cache",
    "body-transformer",
    "ai-prompt-template",
    "ai-prompt-decorator",
    "ai-rag",
    "ai-content-moderation",
    "proxy-mirror",
    "proxy-rewrite",
    "workflow",
    "api-breaker",
    "ai-proxy",
    "ai-proxy-multi",
    "limit-conn",
    "limit-count",
    "limit-req",
    "gzip",
    "server-info",
    "traffic-split",
    "redirect",
    "response-rewrite",
    "degraphql",
    "kafka-proxy",
    "grpc-transcode",
    "grpc-web",
    "http-dubbo",
    "public-api",
    "prometheus",
    "datadog",
    "loki-logger",
    "elasticsearch-logger",
    "echo",
    "loggly",
    "http-logger",
    "splunk-hec-logging",
    "skywalking-logger",
    "google-cloud-logging",
    "sls-logger",
    "tcp-logger",
    "kafka-logger",
    "rocketmq-logger",
    "syslog",
    "udp-logger",
    "file-logger",
    "clickhouse-logger",
    "tencent-cloud-cls",
    "inspect",
    "example-plugin",
    "aws-lambda",
    "azure-functions",
    "openwhisk",
    "openfunction",
    "serverless-post-function",
    "ext-plugin-post-req",
    "ext-plugin-post-resp",
  },
  stream_plugins = { "ip-restriction", "limit-conn", "mqtt-proxy", "syslog" },
  plugin_attr = {
    ["log-rotate"] = {
      timeout = 10000,
      interval = 3600,
      max_kept = 168,
      max_size = -1,
      enable_compression = false
    },
    skywalking = {
      service_name = "APISIX",
      service_instance_name = "APISIX Instance Name",
      endpoint_addr = "http://127.0.0.1:12800",
      report_interval = 3
    },
    opentelemetry = {
      trace_id_source = "x-request-id",
      resource = {
        ["service.name"] = "APISIX"
      },
      collector = {
        address = "127.0.0.1:4318",
        request_timeout = 3,
        request_headers = {
          Authorization = "token"
        }
      },
      batch_span_processor = {
        drop_on_queue_full = false,
        max_queue_size = 1024,
        batch_timeout = 2,
        inactive_timeout = 1,
        max_export_batch_size = tonumber(os.getenv("OTEL_BSP_MAX_EXPORT_BATCH_SIZE")) or 16
      },
      set_ngx_var = false
    },
    prometheus = {
      export_uri = "/apisix/prometheus/metrics",
      metric_prefix = "apisix_",
      enable_export_server = true,
      export_addr = {
        ip = "127.0.0.1",
        port = 9091
      }
    },
    ["server-info"] = {
      report_ttl = 60
    },
    ["dubbo-proxy"] = {
      upstream_multiplex_count = 32
    },
    ["proxy-mirror"] = {
      timeout = {
        connect = "60s",
        read = "60s",
        send = "60s"
      }
    },
    inspect = {
      delay = 3,
      hooks_file = "/usr/local/apisix/plugin_inspect_hooks.lua"
    },
    zipkin = {
      set_ngx_var = false
    }
  },
  deployment = {
    role = "traditional",
    role_traditional = {
      config_provider = "etcd"
    },
    admin = {
      admin_key_required = true,
      admin_key = {
        {
          name = "admin",
          key = "",
          role = "admin"
        }
      },
      enable_admin_cors = true,
      allow_admin = { "127.0.0.0/24" },
      admin_listen = {
        ip = "0.0.0.0",
        port = 9180
      },
      admin_api_version = "v3"
    },
    etcd = {
      host = { "http://127.0.0.1:2379" },
      prefix = "/apisix",
      timeout = 30,
      watch_timeout = 50,
      startup_retry = 2,
      tls = {
        verify = true
      }
    }
  }
}

return _M
