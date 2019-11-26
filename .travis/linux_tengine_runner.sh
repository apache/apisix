#!/usr/bin/env bash
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

set -ex

export_or_prefix() {
    export OPENRESTY_PREFIX="/usr/local/openresty-debug"
}

create_lua_deps() {
    sudo luarocks make --lua-dir=${OPENRESTY_PREFIX}/luajit rockspec/apisix-master-0.rockspec --tree=deps --only-deps --local
    echo "Create lua deps cache"
    sudo rm -rf build-cache/deps
    sudo cp -r deps build-cache/
    sudo cp rockspec/apisix-master-0.rockspec build-cache/
}

before_install() {
    sudo cpanm --notest Test::Nginx >build.log 2>&1 || (cat build.log && exit 1)
}

tengine_install() {
    if [ -d "build-cache${OPENRESTY_PREFIX}" ]; then
        # sudo rm -rf build-cache${OPENRESTY_PREFIX}
        sudo mkdir -p ${OPENRESTY_PREFIX}
        sudo cp -r build-cache${OPENRESTY_PREFIX}/* ${OPENRESTY_PREFIX}/
        ls -l ${OPENRESTY_PREFIX}/
        ls -l ${OPENRESTY_PREFIX}/bin
        return
    fi

    wget https://openresty.org/download/openresty-1.15.8.2.tar.gz
    tar zxf openresty-1.15.8.2.tar.gz
    wget https://codeload.github.com/alibaba/tengine/tar.gz/2.3.2
    tar zxf 2.3.2
    wget https://codeload.github.com/openresty/luajit2/tar.gz/v2.1-20190912
    tar zxf v2.1-20190912
    wget https://codeload.github.com/simplresty/ngx_devel_kit/tar.gz/v0.3.1
    tar zxf v0.3.1

    rm -rf openresty-1.15.8.2/bundle/nginx-1.15.8
    mv tengine-2.3.2 openresty-1.15.8.2/bundle/

    rm -rf openresty-1.15.8.2/bundle/LuaJIT-2.1-20190507
    mv luajit2-2.1-20190912 openresty-1.15.8.2/bundle/

    rm -rf openresty-1.15.8.2/bundle/ngx_devel_kit-0.3.1rc1
    mv ngx_devel_kit-0.3.1 openresty-1.15.8.2/bundle/

    sed -i "s/= auto_complete 'LuaJIT';/= auto_complete 'luajit2';/g" openresty-1.15.8.2/configure
    sed -i 's/= auto_complete "nginx";/= auto_complete "tengine";/g' openresty-1.15.8.2/configure

    cd openresty-1.15.8.2

    ./configure --prefix=${OPENRESTY_PREFIX} --with-debug \
        --with-compat \
        --with-file-aio \
        --with-threads \
        --with-http_addition_module \
        --with-http_auth_request_module \
        --with-http_dav_module \
        --with-http_degradation_module \
        --with-http_flv_module \
        --with-http_gunzip_module \
        --with-http_gzip_static_module \
        --with-http_mp4_module \
        --with-http_random_index_module \
        --with-http_realip_module \
        --with-http_secure_link_module \
        --with-http_ssl_module \
        --with-http_stub_status_module \
        --with-http_sub_module \
        --with-http_v2_module \
        --with-stream \
        --with-stream_ssl_module \
        --with-stream_realip_module \
        --with-stream_ssl_preread_module \
        --with-stream_sni \
        --with-pcre \
        --with-pcre-jit \
        --without-mail_pop3_module \
        --without-mail_imap_module \
        --without-mail_smtp_module \
        --add-module=bundle/tengine-2.3.2/modules/ngx_http_upstream_vnswrr_module/ \
        --add-module=bundle/tengine-2.3.2/modules/mod_dubbo \
        --add-module=bundle/tengine-2.3.2/modules/ngx_multi_upstream_module \
        --add-module=bundle/tengine-2.3.2/modules/mod_config \
        --add-dynamic-module=bundle/tengine-2.3.2/modules/ngx_http_concat_module \
        --add-dynamic-module=bundle/tengine-2.3.2/modules/ngx_http_footer_filter_module \
        --add-dynamic-module=bundle/tengine-2.3.2/modules/ngx_http_proxy_connect_module \
        --add-dynamic-module=bundle/tengine-2.3.2/modules/ngx_http_reqstat_module \
        --add-dynamic-module=bundle/tengine-2.3.2/modules/ngx_http_slice_module \
        --add-dynamic-module=bundle/tengine-2.3.2/modules/ngx_http_sysguard_module \
        --add-dynamic-module=bundle/tengine-2.3.2/modules/ngx_http_trim_filter_module \
        --add-dynamic-module=bundle/tengine-2.3.2/modules/ngx_http_upstream_check_module \
        --add-dynamic-module=bundle/tengine-2.3.2/modules/ngx_http_upstream_consistent_hash_module \
        --add-dynamic-module=bundle/tengine-2.3.2/modules/ngx_http_upstream_dynamic_module \
        --add-dynamic-module=bundle/tengine-2.3.2/modules/ngx_http_upstream_dyups_module \
        --add-dynamic-module=bundle/tengine-2.3.2/modules/ngx_http_upstream_session_sticky_module \
        --add-dynamic-module=bundle/tengine-2.3.2/modules/ngx_http_user_agent_module \
        --add-dynamic-module=bundle/tengine-2.3.2/modules/ngx_slab_stat \
        > build.log 2>&1 || (cat build.log && exit 1)

    make > build.log 2>&1 || (cat build.log && exit 1)

    sudo PATH=$PATH make install > build.log 2>&1 || (cat build.log && exit 1)

    cd ..

    mkdir -p build-cache${OPENRESTY_PREFIX}
    cp -r ${OPENRESTY_PREFIX}/* build-cache${OPENRESTY_PREFIX}
    ls build-cache${OPENRESTY_PREFIX}
    rm -rf openresty-1.15.8.2
}

do_install() {
    export_or_prefix

    sudo apt-get -y update --fix-missing
    sudo apt-get -y install software-properties-common
    sudo add-apt-repository -y ppa:longsleep/golang-backports

    sudo apt-get update

    tengine_install

    sudo luarocks install --lua-dir=${OPENRESTY_PREFIX}/luajit luacov-coveralls

    export GO111MOUDULE=on

    if [ ! -f "build-cache/apisix-master-0.rockspec" ]; then
        create_lua_deps

    else
        src=`md5sum rockspec/apisix-master-0.rockspec | awk '{print $1}'`
        src_cp=`md5sum build-cache/apisix-master-0.rockspec | awk '{print $1}'`
        if [ "$src" = "$src_cp" ]; then
            echo "Use lua deps cache"
            sudo cp -r build-cache/deps ./
        else
            create_lua_deps
        fi
    fi

    git clone https://github.com/iresty/test-nginx.git test-nginx
    wget -P utils https://raw.githubusercontent.com/iresty/openresty-devel-utils/iresty/lj-releng
	chmod a+x utils/lj-releng

    git clone https://github.com/apache/openwhisk-utilities.git .travis/openwhisk-utilities
    cp .travis/ASF* .travis/openwhisk-utilities/scancode/

    ls -l ./
    if [ ! -f "build-cache/grpc_server_example" ]; then
        sudo apt-get install golang

        git clone https://github.com/iresty/grpc_server_example.git grpc_server_example

        cd grpc_server_example/
        go build -o grpc_server_example main.go
        mv grpc_server_example ../build-cache/
        cd ..
    fi
}

script() {
    export_or_prefix
    export PATH=$OPENRESTY_PREFIX/nginx/sbin:$OPENRESTY_PREFIX/luajit/bin:$OPENRESTY_PREFIX/bin:$PATH
    openresty -V
    sudo service etcd start

    ./build-cache/grpc_server_example &

    ./bin/apisix help
    ./bin/apisix init
    ./bin/apisix init_etcd
    ./bin/apisix start
    mkdir -p logs
    sleep 1
    ./bin/apisix stop
    sleep 1
    make lint && make license-check || exit 1
    APISIX_ENABLE_LUACOV=1 prove -Itest-nginx/lib -r t
}

after_success() {
    cat luacov.stats.out
    luacov-coveralls
}

case_opt=$1
shift

case ${case_opt} in
before_install)
    before_install "$@"
    ;;
do_install)
    do_install "$@"
    ;;
script)
    script "$@"
    ;;
after_success)
    after_success "$@"
    ;;
esac
