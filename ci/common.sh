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

rerun_flaky_tests() {
    if tail -1 "$1" | grep "Result: PASS"; then
        exit 0
    fi

    local tests
    local n_test
    tests="$(awk '/^t\/.*.t\s+\(.+ Failed: .+\)/{ print $1 }' "$1")"
    n_test="$(echo "$tests" | wc -l)"
    if [ "$n_test" -eq 0 ] || [ "$n_test" -gt 3 ]; then
        # CI failure failed test or too many tests failed
        exit 1
    fi

    echo "Rerun $(echo "$tests" | xargs)"
    FLUSH_ETCD=1 prove -I./test-nginx/lib -I./ $(echo "$tests" | xargs)
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
    NODEJS_PREFIX="/usr/local/node"
    NODEJS_VERSION="16.13.1"
    wget https://nodejs.org/dist/v${NODEJS_VERSION}/node-v${NODEJS_VERSION}-linux-x64.tar.xz
    tar -xvf node-v${NODEJS_VERSION}-linux-x64.tar.xz
    rm -f /usr/local/bin/node
    rm -f /usr/local/bin/npm
    mv node-v${NODEJS_VERSION}-linux-x64 ${NODEJS_PREFIX}
    ln -s ${NODEJS_PREFIX}/bin/node /usr/local/bin/node
    ln -s ${NODEJS_PREFIX}/bin/npm /usr/local/bin/npm
}

GRPC_SERVER_EXAMPLE_VER=20210819

install_k8s () {
    # create kubernetes cluster using kind
    KIND_VERSION="v0.11.1"
    KUBECTL_VERSION="v1.22.0"
    curl -Lo ./kind "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-$(uname)-amd64"
    curl -Lo ./kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
    chmod +x ./kind
    chmod +x ./kubectl

    echo -e "
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  apiServerAddress: 127.0.0.1
  apiServerPort: 6443
"   >kind.yaml

    ./kind delete cluster --name apisix-test
    ./kind create cluster --name apisix-test --config ./kind.yaml

    echo "wait k8s start..."
    sleep 10
    until [[ $(./kubectl get pods -A --field-selector 'status.phase!=Running' 2>&1) =~ "No resources found" ]]; do
      echo 'still wait k8s start...'
      sleep 1
    done

    echo -e "
kind: ServiceAccount
apiVersion: v1
metadata:
  name: apisix-test
  namespace: default
---
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: apisix-test
rules:
  - apiGroups: [ \"\" ]
    resources: [ endpoints ]
    verbs: [ get,list,watch ]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
    name: apisix-test
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: apisix-test
subjects:
  - kind: ServiceAccount
    name: apisix-test
    namespace: default
"   >apisix-test-rbac.yaml

    ./kubectl apply -f ./apisix-test-rbac.yaml
    ./kubectl proxy -p 6445 &

    KUBERNETES_CLIENT_TOKEN_CONTENT=$(./kubectl get secrets | grep apisix-test | awk '{system("./kubectl get secret -o jsonpath={.data.token} "$1" | base64 --decode")}')

    # if we do not have permission to create folders under the /var/run path, we will use the /tmp as an alternative
    KUBERNETES_CLIENT_TOKEN_DIR="/var/run/secrets/kubernetes.io/serviceaccount"
    KUBERNETES_CLIENT_TOKEN_FILE=${KUBERNETES_CLIENT_TOKEN_DIR}/token

    if ! mkdir -p ${KUBERNETES_CLIENT_TOKEN_DIR}; then
      KUBERNETES_CLIENT_TOKEN_DIR=/tmp${KUBERNETES_CLIENT_TOKEN_DIR}
      KUBERNETES_CLIENT_TOKEN_FILE=/tmp${KUBERNETES_CLIENT_TOKEN_FILE}
      mkdir -p ${KUBERNETES_CLIENT_TOKEN_DIR}
    fi

    if ! echo -n "$KUBERNETES_CLIENT_TOKEN_CONTENT" >${KUBERNETES_CLIENT_TOKEN_FILE}; then
      echo 'save kubernetes token file error'
      exit 1
    fi

    echo 'KUBERNETES_SERVICE_HOST=127.0.0.1'
    echo 'KUBERNETES_SERVICE_PORT=6443'
    echo 'KUBERNETES_CLIENT_TOKEN='"${KUBERNETES_CLIENT_TOKEN_CONTENT}"
    echo 'KUBERNETES_CLIENT_TOKEN_FILE='${KUBERNETES_CLIENT_TOKEN_FILE}

}
