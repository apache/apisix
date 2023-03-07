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

package = "apisix"
version = "3.2.0-0"
supported_platforms = {"linux", "macosx"}

source = {
    url = "git://github.com/apache/apisix",
    branch = "3.2.0",
}

description = {
    summary = "Apache APISIX is a cloud-native microservices API gateway, delivering the ultimate performance, security, open source and scalable platform for all your APIs and microservices.",
    homepage = "https://github.com/apache/apisix",
    license = "Apache License 2.0",
}

dependencies = {
    "lua-resty-ctxdump = 0.1-0",
    "api7-lua-resty-dns-client = 7.0.1",
    "lua-resty-template = 2.0",
    "lua-resty-etcd = 1.10.3",
    "api7-lua-resty-http = 0.2.0",
    "lua-resty-balancer = 0.04",
    "lua-resty-ngxvar = 0.5.2",
    "lua-resty-jit-uuid = 0.0.7",
    "lua-resty-healthcheck-api7 = 2.2.2",
    "api7-lua-resty-jwt = 0.2.4",
    "lua-resty-hmac-ffi = 0.05",
    "lua-resty-cookie = 0.1.0",
    "lua-resty-session = 3.10",
    "opentracing-openresty = 0.1",
    "lua-resty-radixtree = 2.8.2",
    "lua-protobuf = 0.4.1",
    "lua-resty-openidc = 1.7.5",
    "luafilesystem = 1.7.0-2",
    "api7-lua-tinyyaml = 0.4.2",
    "nginx-lua-prometheus = 0.20220527",
    "jsonschema = 0.9.8",
    "lua-resty-ipmatcher = 0.6.1",
    "lua-resty-kafka = 0.20-0",
    "lua-resty-logger-socket = 2.0.1-0",
    "skywalking-nginx-lua = 0.6.0",
    "base64 = 1.5-2",
    "binaryheap = 0.4",
    "api7-dkjson = 0.1.1",
    "resty-redis-cluster = 1.02-4",
    "lua-resty-expr = 1.3.2",
    "graphql = 0.0.2",
    "argparse = 0.7.1-1",
    "luasocket = 3.1.0-1",
    "luasec = 0.9-1",
    "lua-resty-consul = 0.3-2",
    "penlight = 1.9.2-1",
    "ext-plugin-proto = 0.6.0",
    "casbin = 1.41.5",
    "api7-snowflake = 2.0-1",
    "inspect == 3.1.1",
    "lualdap = 1.2.6-1",
    "lua-resty-rocketmq = 0.3.0-0",
    "opentelemetry-lua = 0.2-3",
    "net-url = 0.9-1",
    "xml2lua = 1.5-2",
    "nanoid = 0.1-1",
    "lua-resty-mediador = 0.1.2-1",
    "lua-resty-ldap = 0.1.0-0"
}

build = {
    type = "make",
    build_variables = {
        CFLAGS="$(CFLAGS)",
        LIBFLAG="$(LIBFLAG)",
        LUA_LIBDIR="$(LUA_LIBDIR)",
        LUA_BINDIR="$(LUA_BINDIR)",
        LUA_INCDIR="$(LUA_INCDIR)",
        LUA="$(LUA)",
        OPENSSL_INCDIR="$(OPENSSL_INCDIR)",
        OPENSSL_LIBDIR="$(OPENSSL_LIBDIR)",
    },
    install_variables = {
        ENV_INST_PREFIX="$(PREFIX)",
        ENV_INST_BINDIR="$(BINDIR)",
        ENV_INST_LIBDIR="$(LIBDIR)",
        ENV_INST_LUADIR="$(LUADIR)",
        ENV_INST_CONFDIR="$(CONFDIR)",
    },
}
