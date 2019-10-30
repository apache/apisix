package = "apisix"
version = "0.7-0"
supported_platforms = {"linux", "macosx"}

source = {
    url = "git://github.com/apache/incubator-apisix",
    branch = "v0.7",
}

description = {
    summary = "APISIX is a cloud-native microservices API gateway, delivering the ultimate performance, security, open source and scalable platform for all your APIs and microservices.",
    homepage = "https://github.com/apache/incubator-apisix",
    license = "Apache License 2.0",
    maintainer = "Yuansheng Wang <membphis@gmail.com>"
}

dependencies = {
    "lua-resty-template = 1.9",
    "lua-resty-etcd = 0.6",
    "lua-resty-balancer = 0.02rc5",
    "lua-resty-ngxvar = 0.3",
    "lua-resty-jit-uuid = 0.0.7",
    "rapidjson = 0.6.1",
    "lua-resty-healthcheck-iresty = 1.0.1",
    "lua-resty-jwt = 0.2.0",
    "lua-resty-cookie = 0.1.0",
    "lua-resty-session = 2.24",
    "opentracing-openresty = 0.1",
    "lua-resty-radixtree = 0.7",
    "lua-resty-iputils = 0.3.0-1",
    "lua-protobuf = 0.3.1",
    "lua-resty-openidc = 1.7.2-1",
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
    },
    install_variables = {
        INST_PREFIX="$(PREFIX)",
        INST_BINDIR="$(BINDIR)",
        INST_LIBDIR="$(LIBDIR)",
        INST_LUADIR="$(LUADIR)",
        INST_CONFDIR="$(CONFDIR)",
    },
}
