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

#!/bin/bash

set -ex

install_dependencies() {
    # add OpenResty source
    wget -qO - https://openresty.org/package/pubkey.gpg | sudo apt-key add -
    sudo apt-get update
    sudo apt-get -y install software-properties-common
    sudo add-apt-repository -y "deb http://openresty.org/package/ubuntu $(lsb_release -sc) main"
    sudo apt-get update

    # install OpenResty and some compilation tools
    sudo apt-get install -y git openresty curl luarocks

    # install wrk
    sudo apt-get install -y build-essential libssl-dev
    git clone https://github.com/wg/wrk.git wrk
    cd wrk
    make
    sudo cp wrk /usr/local/bin
}

run_apisix() {
    export PATH=/usr/local/openresty/nginx/sbin:/usr/local/openresty/bin:$PATH
    make deps
    make init
    make run

    # create route
    curl -i http://127.0.0.1:9080/apisix/admin/routes/1 \
    -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' \
    -X PUT -d '
    {
    "uri": "/index.html",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:80": 1
        }
    }
    }'
}

run_test() {
    # wrk -c100 -d30 --latency http://127.0.0.1:9080/index.html > ~/work/apisix/apisix/utils/performance.log
    for((i=1;i<=100;i++));  
    do   
    wrk -c100 -d30 --latency http://127.0.0.1:9080/index.html > ~/work/apisix/apisix/utils/performance.log
    grep "^Requests/sec:" ~/work/apisix/apisix/utils/performance.log | awk {'print $2'}
    sleep 10
    done 
}

check_result() {
    result=`grep "^Requests/sec:" ~/work/apisix/apisix/utils/performance.log | awk {'print $2'}`
    if [[ $result<100 ]];then
        exit 125
    fi
}

case_opt=$1
case $case_opt in
    (install_dependencies)
        install_dependencies
        ;;
    (run_apisix)
        run_apisix
        ;;
    (run_test)
        run_test
        ;;
    (check_result)
        check_result
        ;;
esac
