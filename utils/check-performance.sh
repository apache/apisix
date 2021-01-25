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

    # install sysbench
    curl -s https://packagecloud.io/install/repositories/akopytov/sysbench/script.deb.sh | sudo bash
    sudo apt -y install sysbench
}

run_apisix() {
    export PATH=/usr/local/openresty/nginx/sbin:/usr/local/openresty/bin:$PATH
    make deps
    make init
    sed -i 's/worker_processes: auto/worker_processes: 1/g' ~/work/apisix/apisix/conf/config-default.yaml
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

get_cpu_perf() {
    sysbench cpu --cpu-max-prime=20000 --threads=1 run > ~/work/apisix/apisix/utils/sysbench.log
    grep ".*total number of events:" ~/work/apisix/apisix/utils/sysbench.log | awk {'print int($5)'}
    cat /proc/cpuinfo | grep 'model name'
}

run_test() {
    get_cpu_perf
    for((i=0;i<5;i++));
    do
        wrk -c100 -d30 -t1 --latency http://127.0.0.1:9080/index.html > ~/work/apisix/apisix/utils/performance.log
        result=`grep "^Requests/sec:" ~/work/apisix/apisix/utils/performance.log | awk {'print int($2)'}`
        result_array[i]=$result
        sleep 10
    done
    # sort the array
    IFS=$'\n' result_array=($(sort -n <<<"${result_array[*]}")); unset IFS
    length=${#result_array[*]}
    sum=0
    # remove the highest and lowest values
    for(( i=1;i<$length-1;i++));
    do
        let sum=sum+${result_array[$i]}
    done
    length=`expr $length - 2`
    result=`expr $sum / $length`
    if [[ $result<18000 ]];then
        printf "result: %s\n" "$result"
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
esac
