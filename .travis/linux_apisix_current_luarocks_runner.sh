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

. ./.travis/common.sh

do_install() {
    export_or_prefix

    ./utils/linux-install-openresty.sh
    ./utils/linux-install-luarocks.sh
    ./utils/linux-install-etcd-client.sh
}

script() {
    export_or_prefix
    openresty -V

    sudo rm -rf /usr/local/apisix

    # install APISIX with local version
    sudo luarocks install rockspec/apisix-master-0.rockspec --only-deps  > build.log 2>&1 || (cat build.log && exit 1)
    sudo luarocks make rockspec/apisix-master-0.rockspec > build.log 2>&1 || (cat build.log && exit 1)

    mkdir cli_tmp && cd cli_tmp

    # show install file
    luarocks show apisix

    sudo PATH=$PATH apisix help
    sudo PATH=$PATH apisix init
    sudo PATH=$PATH apisix start
    sudo PATH=$PATH apisix stop

    cat /usr/local/apisix/logs/error.log | grep '\[error\]' > /tmp/error.log | true
    if [ -s /tmp/error.log ]; then
        echo "=====found error log====="
        cat /usr/local/apisix/logs/error.log
        exit 1
    fi

    cd ..

    # apisix cli test
    for f in ./.travis/apisix_cli_test/test_*.sh; do
        sudo PATH="$PATH" "$f"
    done
}

case_opt=$1
shift

case ${case_opt} in
do_install)
    do_install "$@"
    ;;
script)
    script "$@"
    ;;
esac
