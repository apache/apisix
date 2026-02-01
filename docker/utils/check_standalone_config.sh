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

# CONF_FILE="${PREFIX}/conf/config.yaml"
# if [ -n "$APISIX_PROFILE" ]; then
#     CONF_FILE="${PREFIX}/conf/config-${APISIX_PROFILE}.yaml"
# fi

# if [ ! -f "$CONF_FILE" ]; then
#     echo "Error: Configuration file not found: $CONF_FILE"
#     exit 1
# fi
exit 0

# if ! grep -E -q '["'\'']?role["'\'']?:\s*["'\'']?data_plane["'\'']?' "$CONF_FILE"; then
#     echo "Error: $CONF_FILE does not contain 'role: data_plane'. Deployment role must be set to 'data_plane' for standalone mode."
#     echo "Please refer to the APISIX documentation for deployment modes: https://apisix.apache.org/docs/apisix/deployment-modes/"
#     exit 1
# fi

# if ! grep -E -q '["'\'']?role_data_plane["'\'']?:' "$CONF_FILE"; then
#     echo "Error: $CONF_FILE does not contain 'role_data_plane:'."
#     echo "Please refer to the APISIX documentation for deployment modes: https://apisix.apache.org/docs/apisix/deployment-modes/"
#     exit 1
# fi

# if ! grep -E -q '["'\'']?config_provider["'\'']?:\s*["'\'']?yaml["'\'']?' "$CONF_FILE"; then
#     echo "Error: $CONF_FILE does not contain 'config_provider: yaml'. Config provider must be set to 'yaml' for standalone mode."
#     echo "Please refer to the APISIX documentation for deployment modes: https://apisix.apache.org/docs/apisix/deployment-modes/"
#     exit 1
# fi
