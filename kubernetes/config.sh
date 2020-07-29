#!/bin/sh
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


export etcd_url='http://$ETCD_IP_ADDRESS:2379'

wget https://raw.githubusercontent.com/apache/incubator-apisix/master/conf/config.yaml

sed -i -e ':a' -e 'N' -e '$!ba' -e "s/allow_admin[a-z: #\/._]*\n\( *- [0-9a-zA-Z: #\/._',]*\n*\)*//g" config.yaml

sed -i -e "s%http://[0-9.]*:2379%`echo $etcd_url`%g" config.yaml

sed -i -e '/#CONFIG_YAML#/{r config.yaml' -e 'd}' apisix-gw-config-cm.yaml

