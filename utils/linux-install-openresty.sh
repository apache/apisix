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
set -euo pipefail

if [ "$OPENRESTY_VERSION" == "source" ]; then
    cd ..

    wget https://openresty.org/download/openresty-1.19.3.1.tar.gz
    tar -zxvpf openresty-1.19.3.1.tar.gz

    git clone --depth=1 https://github.com/api7/ngx_multi_upstream_module.git
    cd ngx_multi_upstream_module || exit 1
    ./patch.sh ../openresty-1.19.3.1

    git clone --depth=1 https://github.com/api7/mod_dubbo.git ../mod_dubbo

    cd ../openresty-1.19.3.1 || exit 1
    ./configure --prefix="/usr/local/openresty-debug" \
        --add-module=../mod_dubbo --add-module=../ngx_multi_upstream_module \
        --with-debug \
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
        --with-luajit-xcflags='-DLUAJIT_NUMMODE=2 -DLUAJIT_ENABLE_LUA52COMPAT'
    make
    sudo make install

    sudo apt-get install lua5.1 liblua5.1-0-dev

    exit 0
fi

wget -qO - https://openresty.org/package/pubkey.gpg | sudo apt-key add -
sudo apt-get -y update --fix-missing
sudo apt-get -y install software-properties-common
sudo add-apt-repository -y "deb https://openresty.org/package/ubuntu $(lsb_release -sc) main"

sudo apt-get update

if [ "$OPENRESTY_VERSION" == "default" ]; then
    openresty='openresty-debug'
else
    openresty="openresty-debug=$OPENRESTY_VERSION*"
fi

sudo apt-get install "$openresty" lua5.1 liblua5.1-0-dev
