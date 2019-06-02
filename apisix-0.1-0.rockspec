package = "apisix"
version = "0.1-0"
source = {
   url = "git://github.com/iresty/apisix",
   tag = "v0.1",
}

description = {
   summary = "APISIX is a cloud-native microservices API gateway, delivering the ultimate performance, security, open source and scalable platform for all your APIs and microservices.",
   homepage = "https://github.com/iresty/apisix",
   license = "Apache License 2.0",
   maintainer = "Yuansheng Wang <membphis@gmail.com>"
}

dependencies = {
   "lua-resty-libr3 = 0.2",
   "lua-resty-etcd = 0.4",
   "lua-resty-balancer = 0.02rc5",
   "lua-resty-ngxvar = 0.2",
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
