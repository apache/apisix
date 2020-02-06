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

#check_result shell_name exit_code
check_result()
{
  #echo "input params:$1"
  if [ $2 -ne 0 ]; then
     echo "shell:$1 exec failed. exit code:$2"
     exit $2
  fi
}

do_install() {
    wget -qO - https://openresty.org/package/pubkey.gpg | sudo apt-key add -
    sudo apt-get -y update --fix-missing
    sudo apt-get -y install software-properties-common
    sudo add-apt-repository -y "deb http://openresty.org/package/ubuntu $(lsb_release -sc) main"
    sudo add-apt-repository -y ppa:longsleep/golang-backports

    sudo apt-get update
    sudo apt-get install openresty-debug
}

script() {
    export_or_prefix
    export PATH=$OPENRESTY_PREFIX/nginx/sbin:$OPENRESTY_PREFIX/luajit/bin:$OPENRESTY_PREFIX/bin:$PATH
    openresty -V
    sudo service etcd start

    # install APISIX by shell
    sudo mkdir -p /usr/local/apisix/deps
    sudo PATH=$PATH ./utils/install-apisix.sh install

    sudo apisix help
    sudo apisix init
    sudo apisix start
    sudo bash .travis/check-nginxconf.sh
    check_result ".travis/check-nginxconf.sh" $?
    sudo apisix stop

    sudo PATH=$PATH ./utils/install-apisix.sh remove

    # install APISIX by luarocks
    sudo luarocks install rockspec/apisix-master-0.rockspec

    sudo apisix help
    sudo apisix init
    sudo apisix start
    sudo bash .travis/check-nginxconf.sh
    check_result ".travis/check-nginxconf.sh" $?
    sudo apisix stop

    sudo luarocks remove rockspec/apisix-master-0.rockspec
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
