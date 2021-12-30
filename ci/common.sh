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
    export APISIX_MAIN="https://raw.githubusercontent.com/apache/incubator-apisix/master/rockspec/apisix-master-0.rockspec"
    export PATH=$OPENRESTY_PREFIX/nginx/sbin:$OPENRESTY_PREFIX/luajit/bin:$OPENRESTY_PREFIX/bin:$PATH
}

create_lua_deps() {
    echo "Create lua deps"

    make deps
    # maybe reopen this feature later
    # luarocks install luacov-coveralls --tree=deps --local > build.log 2>&1 || (cat build.log && exit 1)
}

install_grpcurl () {
    # For more versions, visit https://github.com/fullstorydev/grpcurl/releases
    GRPCURL_VERSION="1.8.5"
    wget https://github.com/fullstorydev/grpcurl/releases/download/v${GRPCURL_VERSION}/grpcurl_${GRPCURL_VERSION}_linux_x86_64.tar.gz
    tar -xvf grpcurl_${GRPCURL_VERSION}_linux_x86_64.tar.gz -C /usr/local/bin
}

install_vault_cli () {
    VAULT_VERSION="1.9.0"
    wget https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip
    unzip vault_${VAULT_VERSION}_linux_amd64.zip && mv ./vault /usr/local/bin
}

install_nodejs () {
    NODEJS_VERSION="16.13.1"
    wget https://nodejs.org/dist/v${NODEJS_VERSION}/node-v${NODEJS_VERSION}-linux-x64.tar.xz
    tar -xvf node-v16.13.1-linux-x64.tar.xz
    mv node-v16.13.1-linux-x64/bin/node /usr/local/bin/node
    chmod +x /usr/local/bin/node
    mv node-v16.13.1-linux-x64/bin/npm /usr/local/bin/npm
    chmod +x /usr/local/bin/npm
}

install_protobuf () {
    PROTOBUF_VERSION="3.19.0"
    wget https://github.com/protocolbuffers/protobuf/releases/download/v${PROTOBUF_VERSION}/protoc-${PROTOBUF_VERSION}-linux-x86_64.zip
    unzip protoc-${PROTOBUF_VERSION}-linux-x86_64.zip
    mv bin/protoc /usr/local/bin/protoc
    mv include/google /usr/local/include/
    chmod +x /usr/local/bin/protoc

    PROTO_GO_PLUGIN_VER="1.2.0"
    wget https://github.com/grpc/grpc-go/releases/download/cmd/protoc-gen-go-grpc/v${PROTO_GO_PLUGIN_VER}/protoc-gen-go-grpc.v${PROTO_GO_PLUGIN_VER}.linux.amd64.tar.gz
    tar -zxvf protoc-gen-go-grpc.v${PROTO_GO_PLUGIN_VER}.linux.amd64.tar.gz
    mv protoc-gen-go-grpc /usr/local/bin/protoc-gen-go
    chmod +x /usr/local/bin/protoc-gen-go

    PROTO_JS_PLUGIN_VER="1.3.0"
    wget https://github.com/grpc/grpc-web/releases/download/${PROTO_JS_PLUGIN_VER}/protoc-gen-grpc-web-${PROTO_JS_PLUGIN_VER}-linux-x86_64
    mv protoc-gen-grpc-web-${PROTO_JS_PLUGIN_VER}-linux-x86_64 /usr/local/bin/protoc-gen-grpc-web
    chmod +x /usr/local/bin/protoc-gen-grpc-web
}

GRPC_SERVER_EXAMPLE_VER=20210819
