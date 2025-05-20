#!/bin/bash
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

# 'make init' operates scripts and related configuration files in the current directory
# The 'apisix' command is a command in the /usr/local/apisix,
# and the configuration file for the operation is in the /usr/local/apisix/conf
set -euxo pipefail
setup() {
  # create root user
  echo root | etcdctl user add root --interactive=false || true
  etcdctl role add root || true
  etcdctl role grant-permission root --prefix=true readwrite /
  etcdctl user grant-role root root

  # create readonly user
  echo readonlypass | etcdctl user add readonly --interactive=false || true
  etcdctl role add readonly || true
  etcdctl role grant-permission readonly --prefix=true read /
  etcdctl user grant-role readonly readonly

  # enable auth
  etcdctl auth enable
}

cleanup() {
  etcdctl --user=root --password=root auth disable
  etcdctl user delete root
  etcdctl role delete root
  etcdctl user delete readonly
  etcdctl role delete readonly
}

case "${1:-}" in
  setup)
    setup
    ;;
  cleanup)
    cleanup
    ;;
  *)
    echo "Usage: $0 {setup|cleanup}"
    exit 1
    ;;
esac
