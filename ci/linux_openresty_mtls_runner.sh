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

. ./ci/common.sh

before_install() {
    sudo cpanm --notest Test::Nginx >build.log 2>&1 || (cat build.log && exit 1)
}

do_install() {
    export_or_prefix

    ./utils/linux-install-openresty.sh

    ./utils/linux-install-luarocks.sh

    for (( i = 0; i < 10; i++ )); do
        if [[ "$i" -eq 10 ]]; then
            echo "failed to install luacheck in time"
            cat build.log && exit 1
            exit 1
        fi
        sudo luarocks install luacheck > build.log 2>&1 && break
        i=$(( i + 1 ))
    done

    ./utils/linux-install-etcd-client.sh

    create_lua_deps

    # sudo apt-get install tree -y
    # tree deps

    git clone https://github.com/iresty/test-nginx.git test-nginx
    make utils

    git clone https://github.com/apache/openwhisk-utilities.git ci/openwhisk-utilities
    cp ci/ASF* ci/openwhisk-utilities/scancode/

    ls -l ./
}

script() {
    export_or_prefix
    openresty -V


    # enable mTLS
    echo "
apisix:
    port_admin: 9180
    https_admin: true

    admin_api_mtls:
        admin_ssl_cert: "../t/certs/mtls_server.crt"
        admin_ssl_cert_key: "../t/certs/mtls_server.key"
        admin_ssl_ca_cert: "../t/certs/mtls_ca.crt"

" > conf/config.yaml

    ./bin/apisix help
    ./bin/apisix init
    ./bin/apisix init_etcd
    ./bin/apisix start

    sleep 1
    cat logs/error.log


    echo "127.0.0.1 admin.apisix.dev" | sudo tee -a /etc/hosts

    # correct certs
    code=$(curl -i -o /dev/null -s -w %{http_code}  --cacert ./t/certs/mtls_ca.crt --key ./t/certs/mtls_client.key --cert ./t/certs/mtls_client.crt -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' https://admin.apisix.dev:9180/apisix/admin/routes)
    if [ ! $code -eq 200 ]; then
        echo "failed: failed to enabled mTLS for admin"
        exit 1
    fi

    # # no certs
    # code=$(curl -i -o /dev/null -s -w %{http_code} -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' https://admin.apisix.dev:9180/apisix/admin/routes)
    # if [ ! $code -eq 000 ]; then
    #     echo "failed: failed to enabled mTLS for admin"
    #     exit 1
    # fi

    # # no ca cert
    # code=$(curl -i -o /dev/null -s -w %{http_code} --key ./t/certs/mtls_client.key --cert ./t/certs/mtls_client.crt -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' https://admin.apisix.dev:9180/apisix/admin/routes)
    # if [ ! $code -eq 000 ]; then
    #     echo "failed: failed to enabled mTLS for admin"
    #     exit 1
    # fi

    # # error key
    # code=$(curl -i -o /dev/null -s -w %{http_code}  --cacert ./t/certs/mtls_ca.crt --key ./t/certs/mtls_server.key --cert ./t/certs/mtls_client.crt -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' https://admin.apisix.dev:9180/apisix/admin/routes)
    # if [ ! $code -eq 000 ]; then
    #     echo "failed: failed to enabled mTLS for admin"
    #     exit 1
    # fi

    # skip
    code=$(curl -i -o /dev/null -s -w %{http_code} -k -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' https://admin.apisix.dev:9180/apisix/admin/routes)
    if [ ! $code -eq 400 ]; then
        echo "failed: failed to enabled mTLS for admin"
        exit 1
    fi

    ./bin/apisix stop
    sleep 1

    make lint && make license-check || exit 1
}

after_success() {
    #cat luacov.stats.out
    #luacov-coveralls
    echo "done"
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
