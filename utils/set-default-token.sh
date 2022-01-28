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

# download yq cli
YQ_VERSION="4.17.2"
wget https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_amd64
mv ./yq_linux_amd64 /usr/local/bin/yamlq
chmod +x /usr/local/bin/yamlq
ln -s /usr/local/bin/yamlq /usr/bin/yamlq

# set default admin token
sudo yamlq e -i '.apisix.admin_key[0].key = "edd1c9f034335f136f87ad84b625c8f1"' conf/config-default.yaml
sudo yamlq e -i '.apisix.admin_key[1].key = "4054f7cf07e344346cd3f287985e76a2"' conf/config-default.yaml

# set default admin token env variable
export APISIX_ADMIN_API_TOKEN="edd1c9f034335f136f87ad84b625c8f1"
