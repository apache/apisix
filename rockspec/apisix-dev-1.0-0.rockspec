package = "apisix-dev"
version = "1.0-0"
supported_platforms = {"linux", "macosx"}

source = {
    url = "git://github.com/iresty/apisix",
    branch = "master",
}

description = {
    summary = "APISIX is a cloud-native microservices API gateway, delivering the ultimate performance, security, open source and scalable platform for all your APIs and microservices.",
    homepage = "https://github.com/iresty/apisix",
    license = "Apache License 2.0",
    maintainer = "Yuansheng Wang <membphis@gmail.com>"
}

dependencies = {
    "lua-resty-libr3",
    "lua-resty-template",
    "lua-resty-etcd",
    "lua-resty-balancer",
    "lua-resty-ngxvar",
    "lua-resty-jit-uuid",
    "rapidjson",
    "lua-resty-healthcheck-iresty",
    "lua-resty-jwt",
    "lua-resty-cookie",
    "lua-resty-session",
    "lua-resty-openidc",
    "opentracing-openresty",
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
