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
    HOMEBREW_NO_AUTO_UPDATE=1 brew install perl cpanminus etcd luarocks openresty/brew/openresty-debug redis@3.2
    brew upgrade go

    sudo sed -i "" "s/requirepass/#requirepass/g" /usr/local/etc/redis.conf
    brew services start redis@3.2

    export GO111MOUDULE=on
    sudo cpanm --notest Test::Nginx >build.log 2>&1 || (cat build.log && exit 1)
    export_or_prefix
    luarocks install --lua-dir=${OPENRESTY_PREFIX}/luajit luacov-coveralls --local --tree=deps

    # spin up kafka cluster for tests (1 zookeper and 1 kafka instance)
    export ZK_VER=3.5.7
    export SCALA_VER=2.11
    export KAFKA_VER=2.4.0

    if [ ! -f download-cache/kafka_$SCALA_VER-$KAFKA_VER.tgz ]; then wget -P download-cache http://mirrors.tuna.tsinghua.edu.cn/apache/kafka/$KAFKA_VER/kafka_$SCALA_VER-$KAFKA_VER.tgz;fi
    if [ ! -f download-cache/apache-zookeeper-$ZK_VER-bin.tar.gz ]; then wget -P download-cache https://mirrors.tuna.tsinghua.edu.cn/apache/zookeeper/zookeeper-$ZK_VER/apache-zookeeper-$ZK_VER-bin.tar.gz;fi

    sudo tar -xzf download-cache/apache-zookeeper-$ZK_VER-bin.tar.gz -C /usr/local/
    sudo tar -xzf download-cache/kafka_$SCALA_VER-$KAFKA_VER.tgz -C /usr/local/
    sudo mv /usr/local/kafka_$SCALA_VER-$KAFKA_VER /usr/local/kafka
    sudo mv /usr/local/apache-zookeeper-$ZK_VER-bin /usr/local/zookeeper
    sudo cp /usr/local/zookeeper/conf/zoo_sample.cfg /usr/local/zookeeper/conf/zoo.cfg
    sudo sed -i '' '$a\
    host\.name=127.0.0.1' /usr/local/kafka/config/server.properties
    sudo /usr/local/zookeeper/bin/zkServer.sh start
    sudo /usr/local/kafka/bin/kafka-server-start.sh  -daemon /usr/local/kafka/config/server.properties
    sleep 1
    /usr/local/kafka/bin/kafka-topics.sh --create --zookeeper localhost:2181  --replication-factor 1 --partitions 2 --topic test2
}

do_install() {
    export_or_prefix

    make deps

    git clone https://github.com/iresty/test-nginx.git test-nginx

    wget -P utils https://raw.githubusercontent.com/openresty/openresty-devel-utils/master/lj-releng
	chmod a+x utils/lj-releng

    wget https://github.com/iresty/grpc_server_example/releases/download/20200314/grpc_server_example-darwin-amd64.tar.gz
    tar -xvf grpc_server_example-darwin-amd64.tar.gz

    brew install grpcurl
}

script() {
    export_or_prefix
    export PATH=$OPENRESTY_PREFIX/nginx/sbin:$OPENRESTY_PREFIX/luajit/bin:$OPENRESTY_PREFIX/bin:$PATH

    etcd --enable-v2=true &
    sleep 1

    ./grpc_server_example &

    make help
    make init
    sudo make run
    mkdir -p logs
    sleep 1

    sudo make stop

    sleep 1

    ln -sf $PWD/deps/lib $PWD/deps/lib64
    sudo mkdir -p /usr/local/var/log/nginx/
    sudo touch /usr/local/var/log/nginx/error.log
    sudo chmod 777 /usr/local/var/log/nginx/error.log
    APISIX_ENABLE_LUACOV=1 prove -Itest-nginx/lib -I./ -r t/admin/*.t
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
