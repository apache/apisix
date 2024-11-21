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
export OPENRESTY_VERSION=source
export SSL_LIB_VERSION=tongsuo


before_install() {
    if [ -n "$COMPILE_TONGSUO" ]; then
        git clone https://github.com/api7/tongsuo --depth 1
        pushd tongsuo
        # build binary
        ./config enable-ntls -static
        make -j2
        mv apps/openssl apps/static-openssl
        ./config shared enable-ntls -g --prefix=/usr/local/tongsuo
        make -j2
        popd
    fi

    pushd tongsuo
    sudo make install_sw
    sudo cp apps/static-openssl /usr/local/tongsuo/bin/openssl
    export PATH=/usr/local/tongsuo/bin:$PATH
    openssl version
    popd
}


case_opt=$1

case ${case_opt} in
before_install)
    # shellcheck disable=SC2218
    before_install
    ;;
esac

. ./ci/linux_openresty_common_runner.sh
