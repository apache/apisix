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

set -eo pipefail

PREFIX=${APISIX_PREFIX:=/usr/local/apisix}

if [[ "$1" == "docker-start" ]]; then
    if [ "$APISIX_STAND_ALONE" = "true" ]; then
        cat > ${PREFIX}/conf/config.yaml << _EOC_
deployment:
  role: data_plane
  role_data_plane:
    config_provider: yaml
_EOC_

        cat > ${PREFIX}/conf/apisix.yaml << _EOC_
routes:
  -
#END
_EOC_
        /usr/bin/apisix init
    else
        /usr/bin/apisix init
        /usr/bin/apisix init_etcd
    fi
    
    exec /usr/local/openresty-debug/bin/openresty -p /usr/local/apisix -g 'daemon off;'
fi

exec "$@"
