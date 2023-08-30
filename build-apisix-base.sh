#!/usr/bin/env bash
set -euo pipefail
set -x

version=${version:-0.0.0}

OPENRESTY_VERSION=${OPENRESTY_VERSION:-1.21.4.1}
if [ "$OPENRESTY_VERSION" == "source" ] || [ "$OPENRESTY_VERSION" == "default" ]; then
    OPENRESTY_VERSION="1.21.4.1"
fi

if ([ $# -gt 0 ] && [ "$1" == "latest" ]) || [ "$version" == "latest" ]; then
    ngx_multi_upstream_module_ver="master"
    mod_dubbo_ver="master"
    apisix_nginx_module_ver="main"
    wasm_nginx_module_ver="main"
    lua_var_nginx_module_ver="master"
    grpc_client_nginx_module_ver="main"
    amesh_ver="main"
    debug_args="--with-debug"
    OR_PREFIX=${OR_PREFIX:="/usr/local/openresty-debug"}
else
    ngx_multi_upstream_module_ver="1.1.1"
    mod_dubbo_ver="1.0.2"
    apisix_nginx_module_ver="1.12.0"
    wasm_nginx_module_ver="0.6.5"
    lua_var_nginx_module_ver="v0.5.3"
    grpc_client_nginx_module_ver="v0.4.3"
    amesh_ver="main"
    debug_args=${debug_args:-}
    OR_PREFIX=${OR_PREFIX:="/usr/local/openresty"}
fi

prev_workdir="$PWD"
repo=$(basename "$prev_workdir")
workdir=$(mktemp -d)
cd "$workdir" || exit 1

wget --no-check-certificate https://openresty.org/download/openresty-${OPENRESTY_VERSION}.tar.gz
tar -zxvpf openresty-${OPENRESTY_VERSION}.tar.gz > /dev/null

if [ "$repo" == ngx_multi_upstream_module ]; then
    cp -r "$prev_workdir" ./ngx_multi_upstream_module-${ngx_multi_upstream_module_ver}
else
    git clone --depth=1 -b $ngx_multi_upstream_module_ver \
        https://github.com/api7/ngx_multi_upstream_module.git \
        ngx_multi_upstream_module-${ngx_multi_upstream_module_ver}
fi

if [ "$repo" == mod_dubbo ]; then
    cp -r "$prev_workdir" ./mod_dubbo-${mod_dubbo_ver}
else
    git clone --depth=1 -b $mod_dubbo_ver \
        https://github.com/api7/mod_dubbo.git \
        mod_dubbo-${mod_dubbo_ver}
fi

if [ "$repo" == apisix-nginx-module ]; then
    cp -r "$prev_workdir" ./apisix-nginx-module-${apisix_nginx_module_ver}
else
    git clone --depth=1 -b $apisix_nginx_module_ver \
        https://github.com/api7/apisix-nginx-module.git \
        apisix-nginx-module-${apisix_nginx_module_ver}
fi

if [ "$repo" == wasm-nginx-module ]; then
    cp -r "$prev_workdir" ./wasm-nginx-module-${wasm_nginx_module_ver}
else
    git clone --depth=1 -b $wasm_nginx_module_ver \
        https://github.com/api7/wasm-nginx-module.git \
        wasm-nginx-module-${wasm_nginx_module_ver}
fi

if [ "$repo" == lua-var-nginx-module ]; then
    cp -r "$prev_workdir" ./lua-var-nginx-module-${lua_var_nginx_module_ver}
else
    git clone --depth=1 -b $lua_var_nginx_module_ver \
        https://github.com/api7/lua-var-nginx-module \
        lua-var-nginx-module-${lua_var_nginx_module_ver}
fi

if [ "$repo" == grpc-client-nginx-module ]; then
    cp -r "$prev_workdir" ./grpc-client-nginx-module-${grpc_client_nginx_module_ver}
else
    git clone --depth=1 -b $grpc_client_nginx_module_ver \
        https://github.com/api7/grpc-client-nginx-module \
        grpc-client-nginx-module-${grpc_client_nginx_module_ver}
fi

if [ "$repo" == amesh ]; then
    cp -r "$prev_workdir" ./amesh-${amesh_ver}
else
    git clone --depth=1 -b $amesh_ver \
        https://github.com/api7/amesh \
        amesh-${amesh_ver}
fi

cd ngx_multi_upstream_module-${ngx_multi_upstream_module_ver} || exit 1
./patch.sh ../openresty-${OPENRESTY_VERSION}
cd ..

cd apisix-nginx-module-${apisix_nginx_module_ver}/patch || exit 1
./patch.sh ../../openresty-${OPENRESTY_VERSION}
cd ../..

cd wasm-nginx-module-${wasm_nginx_module_ver} || exit 1
./install-wasmtime.sh
cd ..

cc_opt=${cc_opt:-}
ld_opt=${ld_opt:-}
luajit_xcflags=${luajit_xcflags:="-DLUAJIT_NUMMODE=2 -DLUAJIT_ENABLE_LUA52COMPAT"}
no_pool_patch=${no_pool_patch:-}
# TODO: remove old NGX_HTTP_GRPC_CLI_ENGINE_PATH once we have released a new
# version of grpc-client-nginx-module
grpc_engine_path="-DNGX_GRPC_CLI_ENGINE_PATH=$OR_PREFIX/libgrpc_engine.so -DNGX_HTTP_GRPC_CLI_ENGINE_PATH=$OR_PREFIX/libgrpc_engine.so"

cd openresty-${OPENRESTY_VERSION} || exit 1

if [[ "$OPENRESTY_VERSION" == 1.21.4.1 ]] || [[ "$OPENRESTY_VERSION" == 1.19.* ]]; then
# FIXME: remove this once 1.21.4.2 is released
rm -rf bundle/LuaJIT-2.1-20220411
lj_ver=2.1-20230119
wget "https://github.com/openresty/luajit2/archive/v$lj_ver.tar.gz" -O "LuaJIT-$lj_ver.tar.gz"
tar -xzf LuaJIT-$lj_ver.tar.gz
mv luajit2-* bundle/LuaJIT-2.1-20220411
fi

or_limit_ver=0.08
if [ ! -d "bundle/lua-resty-limit-traffic-$or_limit_ver" ]; then
    echo "ERROR: the official repository of lua-resty-limit-traffic has been updated, please sync to API7's repository." >&2
    exit 1
else
    rm -rf bundle/lua-resty-limit-traffic-$or_limit_ver
    limit_ver=1.0.0
    wget "https://github.com/api7/lua-resty-limit-traffic/archive/refs/tags/v$limit_ver.tar.gz" -O "lua-resty-limit-traffic-$limit_ver.tar.gz"
    tar -xzf lua-resty-limit-traffic-$limit_ver.tar.gz
    mv lua-resty-limit-traffic-$limit_ver bundle/lua-resty-limit-traffic-$or_limit_ver
fi

CACHE_QUICTLS_HIT=${CACHE_QUICTLS_HIT:-false}
QUICTLS_TAG=${QUICTLS_TAG:-OpenSSL_1_1_1u-quic1}
if [[ $CACHE_QUICTLS_HIT == false ]]; then
(
cd /tmp
git clone https://github.com/quictls/openssl quictls
cd quictls
git checkout ${QUICTLS_TAG}
./config --prefix=/usr/local/openresty/quictls
make install
)
fi

set +e
(
dir=$PWD

cd $dir/bundle/nginx-1.21.4/
patch -f -p1 < ${prev_workdir}/quic.patch

cd $dir/../grpc-client-nginx-module-main
patch -p1 < ${prev_workdir}/grpc-client-nginx-module-main.patch

cd $dir/../ngx_multi_upstream_module-master
patch -p1 < ${prev_workdir}/ngx_multi_upstream_module.patch

cd $dir/../wasm-nginx-module-main
patch -p1 < ${prev_workdir}/wasm-nginx-module-main.patch

cd $dir/bundle/headers-more-nginx-module-0.33/src
patch -p2 < ${prev_workdir}/headers-more-nginx-module.patch

cd $dir/bundle/nginx-1.21.4
patch -p2 < ${prev_workdir}/nginx-1.21.4.patch

cd $dir/bundle/ngx_lua-0.10.21
patch -p1 < ${prev_workdir}/ngx_lua.patch
)
set -e

export_openresty_variables()
{
    export openssl_prefix=/usr/local/openresty/quictls;
    export zlib_prefix=/usr/local/openresty/zlib;
    export pcre_prefix=/usr/local/openresty/pcre;
    export cc_opt="-DNGX_LUA_ABORT_AT_PANIC -I${zlib_prefix}/include -I${pcre_prefix}/include -I${openssl_prefix}/include";
    export ld_opt="-L${zlib_prefix}/lib -L${pcre_prefix}/lib -L${openssl_prefix}/lib -Wl,-rpath,${zlib_prefix}/lib:${pcre_prefix}/lib:${openssl_prefix}/lib"
}

export_openresty_variables

./configure --prefix="$OR_PREFIX" \
    --with-cc-opt="-DAPISIX_BASE_VER=$version $grpc_engine_path $cc_opt" \
    --with-ld-opt="-Wl,-rpath,$OR_PREFIX/wasmtime-c-api/lib $ld_opt" \
    $debug_args \
    --add-module=../mod_dubbo-${mod_dubbo_ver} \
    --add-module=../ngx_multi_upstream_module-${ngx_multi_upstream_module_ver} \
    --add-module=../apisix-nginx-module-${apisix_nginx_module_ver} \
    --add-module=../apisix-nginx-module-${apisix_nginx_module_ver}/src/stream \
    --add-module=../apisix-nginx-module-${apisix_nginx_module_ver}/src/meta \
    --add-module=../wasm-nginx-module-${wasm_nginx_module_ver} \
    --add-module=../lua-var-nginx-module-${lua_var_nginx_module_ver} \
    --add-module=../grpc-client-nginx-module-${grpc_client_nginx_module_ver} \
    --with-poll_module \
    --with-pcre-jit \
    --without-http_rds_json_module \
    --without-http_rds_csv_module \
    --without-lua_rds_parser \
    --with-stream \
    --with-stream_ssl_module \
    --with-stream_ssl_preread_module \
    --with-http_v2_module \
    --without-mail_pop3_module \
    --without-mail_imap_module \
    --without-mail_smtp_module \
    --with-http_stub_status_module \
    --with-http_realip_module \
    --with-http_addition_module \
    --with-http_auth_request_module \
    --with-http_secure_link_module \
    --with-http_random_index_module \
    --with-http_gzip_static_module \
    --with-http_sub_module \
    --with-http_dav_module \
    --with-http_flv_module \
    --with-http_mp4_module \
    --with-http_gunzip_module \
    --with-threads \
    --with-compat \
    --with-luajit-xcflags="$luajit_xcflags" \
    --without-http_srcache_module \
    --without-http_redis_module \
    --without-http_redis2_module \
    --without-pcre2 \
    --with-http_v3_module \
    $no_pool_patch \
    -j`nproc`

make -j`nproc`
sudo make install
cd ..

cd apisix-nginx-module-${apisix_nginx_module_ver} || exit 1
sudo OPENRESTY_PREFIX="$OR_PREFIX" make install
cd ..

cd wasm-nginx-module-${wasm_nginx_module_ver} || exit 1
sudo OPENRESTY_PREFIX="$OR_PREFIX" make install
cd ..

cd grpc-client-nginx-module-${grpc_client_nginx_module_ver} || exit 1
sudo OPENRESTY_PREFIX="$OR_PREFIX" make install
cd ..

cd amesh-${amesh_ver} || exit 1
sudo OPENRESTY_PREFIX="$OR_PREFIX" sh -c 'PATH="${PATH}:/usr/local/go/bin" make install'
cd ..

# package etcdctl
ETCD_ARCH="amd64"
ETCD_VERSION=${ETCD_VERSION:-'3.5.4'}
ARCH=${ARCH:-$(uname -m | tr '[:upper:]' '[:lower:]')}

if [[ $ARCH == "arm64" ]] || [[ $ARCH == "aarch64" ]]; then
    ETCD_ARCH="arm64"
fi

wget -q https://github.com/etcd-io/etcd/releases/download/v${ETCD_VERSION}/etcd-v${ETCD_VERSION}-linux-${ETCD_ARCH}.tar.gz
tar xf etcd-v${ETCD_VERSION}-linux-${ETCD_ARCH}.tar.gz
# ship etcdctl under the same bin dir of openresty so we can package it easily
sudo cp etcd-v${ETCD_VERSION}-linux-${ETCD_ARCH}/etcdctl "$OR_PREFIX"/bin/
rm -rf etcd-v${ETCD_VERSION}-linux-${ETCD_ARCH}
