package = "apisix"
version = "0.5-0"
supported_platforms = {"linux", "macosx"}

source = {
    url = "git://github.com/iresty/apisix",
    tag = "v0.5",
}

description = {
    summary = "APISIX is a cloud-native microservices API gateway, delivering the ultimate performance, security, open source and scalable platform for all your APIs and microservices.",
    homepage = "https://github.com/iresty/apisix",
    license = "Apache License 2.0",
    maintainer = "Yuansheng Wang <membphis@gmail.com>"
}

dependencies = {
    "lua-resty-libr3 = 0.6",
    "lua-resty-template = 1.9-1",
    "lua-resty-etcd = 0.5",
    "lua-resty-balancer = 0.02rc5",
    "lua-resty-ngxvar = 0.3",
    "lua-resty-jit-uuid = 0.0.7",
    "rapidjson = 0.6.0-1",
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
