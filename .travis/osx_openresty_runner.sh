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
    export OPENRESTY_PREFIX=$(brew --prefix openresty/brew/openresty-debug)
}

before_install() {
    HOMEBREW_NO_AUTO_UPDATE=1 brew install perl cpanminus etcd luarocks openresty/brew/openresty-debug redis
    brew upgrade go

    sudo sed -i "" "s/requirepass/#requirepass/g" /usr/local/etc/redis.conf
    brew services start redis

    export GO111MOUDULE=on
    sudo cpanm --notest Test::Nginx >build.log 2>&1 || (cat build.log && exit 1)
    export_or_prefix
    luarocks install --lua-dir=${OPENRESTY_PREFIX}/luajit luacov-coveralls --local --tree=deps
}

do_install() {
    export_or_prefix

    make deps

    git clone https://github.com/iresty/test-nginx.git test-nginx
    git clone https://github.com/iresty/grpc_server_example.git grpc_server_example

    wget -P utils https://raw.githubusercontent.com/openresty/openresty-devel-utils/master/lj-releng
	chmod a+x utils/lj-releng

    cd grpc_server_example/
    go build -o grpc_server_example main.go
    cd ..

    brew install grpcurl
}

script() {
    export_or_prefix
    export PATH=$OPENRESTY_PREFIX/nginx/sbin:$OPENRESTY_PREFIX/luajit/bin:$OPENRESTY_PREFIX/bin:$PATH

    etcd --enable-v2=true &
    sleep 1

    luarocks install luacheck

    sudo cpanm Test::Nginx

    ./grpc_server_example/grpc_server_example &

    make help
    make init
    sudo make run
    mkdir -p logs
    sleep 1

    #test grpc proxy
    curl http://127.0.0.1:9080/apisix/admin/routes/1 -X PUT -d '
    {
        "methods": ["POST", "GET"],
        "uri": "/helloworld.Greeter/SayHello",
        "service_protocol": "grpc",
        "upstream": {
            "type": "roundrobin",
            "nodes": {
                "127.0.0.1:50051": 1
            }
        }
    }'

    grpcurl -insecure -import-path ./grpc_server_example/proto -proto helloworld.proto -d '{"name":"apisix"}' 127.0.0.1:9443 helloworld.Greeter.SayHello

    sleep 1

    sudo make stop

    sleep 1

    ln -sf $PWD/deps/lib $PWD/deps/lib64
    sudo mkdir -p /usr/local/var/log/nginx/
    sudo touch /usr/local/var/log/nginx/error.log
    sudo chmod 777 /usr/local/var/log/nginx/error.log
    APISIX_ENABLE_LUACOV=1 prove -Itest-nginx/lib -I./ -r t
}

after_success() {
    $PWD/deps/bin/luacov-coveralls
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
