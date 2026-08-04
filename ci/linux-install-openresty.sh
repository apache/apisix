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

source ./ci/common.sh

export_version_info

ARCH=${ARCH:-`(uname -m | tr '[:upper:]' '[:lower:]')`}

SSL_LIB_VERSION=${SSL_LIB_VERSION-openssl}
ENABLE_FIPS=${ENABLE_FIPS:-"false"}

if [ "$SSL_LIB_VERSION" == "tongsuo" ] || [ "$ENABLE_FIPS" == "true" ]; then
    arch_path=""
    if [[ $ARCH == "arm64" ]] || [[ $ARCH == "aarch64" ]]; then
        arch_path="arm64/"
    fi

    wget -qO - https://openresty.org/package/pubkey.gpg | sudo apt-key add -
    wget -qO - http://repos.apiseven.com/pubkey.gpg | sudo apt-key add -
    sudo apt-get -y update --fix-missing
    sudo apt-get -y install software-properties-common
    sudo add-apt-repository -y "deb https://openresty.org/package/${arch_path}ubuntu $(lsb_release -sc) main"
    sudo add-apt-repository -y "deb http://repos.apiseven.com/packages/${arch_path}debian bullseye main"

    sudo apt-get update
    sudo apt-get install -y openresty-pcre-dev openresty-zlib-dev build-essential gcc g++ cpanminus libxml2-dev libxslt-dev

    if [ "$SSL_LIB_VERSION" == "tongsuo" ]; then
        export openssl_prefix=/usr/local/tongsuo
        export zlib_prefix=$OPENRESTY_PREFIX/zlib
        export pcre_prefix=$OPENRESTY_PREFIX/pcre

        export cc_opt="-DNGX_LUA_ABORT_AT_PANIC -I${zlib_prefix}/include -I${pcre_prefix}/include -I${openssl_prefix}/include"
        export ld_opt="-L${zlib_prefix}/lib -L${pcre_prefix}/lib -L${openssl_prefix}/lib64 -Wl,-rpath,${zlib_prefix}/lib:${pcre_prefix}/lib:${openssl_prefix}/lib64"
    fi

    install_apisix_runtime

    if [ ! "$ENABLE_FIPS" == "true" ]; then
        curl -o /usr/local/openresty/openssl3/ssl/openssl.cnf \
            https://raw.githubusercontent.com/api7/apisix-build-tools/apisix-runtime/${APISIX_RUNTIME}/conf/openssl3/openssl.cnf
    fi
else
    sudo apt-get -y update --fix-missing
    sudo apt-get install -y build-essential gcc g++ cpanminus libxml2-dev libxslt-dev

    if [ "$APISIX_RUNTIME" != "1.3.11" ]; then
        echo "Please update the apisix-runtime-debug checksum for APISIX_RUNTIME=$APISIX_RUNTIME" >&2
        exit 1
    fi

    case "$ARCH" in
        x86_64|amd64)
            DEB_ARCH="amd64"
            EXPECTED_SHA256="6c03f0a47a80e84c595c7e067f7d05fc69890237f9191af55108a284b356c4ee"
            ;;
        arm64|aarch64)
            DEB_ARCH="arm64"
            EXPECTED_SHA256="cdc124262a1acb2de170f12a2180cdc357ba867d6447cd08a9ba1639994d4e50"
            ;;
        *)
            echo "Unsupported architecture: $ARCH" >&2
            exit 1
            ;;
    esac

    DEB_NAME="apisix-runtime-debug_${APISIX_RUNTIME}-0.debianbookworm-slim_${DEB_ARCH}.deb"
    RELEASE_URL="https://github.com/api7/apisix-build-tools/releases/download/apisix-runtime%2F${APISIX_RUNTIME}/${DEB_NAME}"

    wget --no-verbose --tries=3 --retry-connrefused "$RELEASE_URL" -O "/tmp/$DEB_NAME"
    echo "$EXPECTED_SHA256  /tmp/$DEB_NAME" | sha256sum -c -
    sudo apt-get install -y "/tmp/$DEB_NAME"
    rm -f "/tmp/$DEB_NAME"
fi

# patch lua-resty-events
sed -i 's/log(ERR, "event worker failed: ", perr)/log(ngx.WARN, "event worker failed: ", perr)/' /usr/local/openresty/lualib/resty/events/worker.lua
