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

# Build Java command with proper environment variable expansion
JAVA_ARGS=(
    "-Djava.security.egd=file:/dev/./urandom"
    "-jar"
    "/app.jar"
    "--suffix.num=${SUFFIX_NUM}"
    "--spring.cloud.nacos.discovery.server-addr=${NACOS_ADDR}"
    "--spring.application.name=${SERVICE_NAME}"
    "--spring.cloud.nacos.discovery.group=${GROUP}"
    "--spring.cloud.nacos.discovery.namespace=${NAMESPACE}"
)

# Add metadata dynamically for all METADATA_* environment variables
for var in $(env | grep '^METADATA_' | cut -d= -f1); do
    # Convert METADATA_LANE to lane, METADATA_ENV to env, etc.
    metadata_key=$(echo "${var#METADATA_}" | tr '[:upper:]' '[:lower:]')
    metadata_value=$(eval echo \$${var})

    if [ -n "${metadata_value}" ]; then
        JAVA_ARGS+=("--spring.cloud.nacos.discovery.metadata.${metadata_key}=${metadata_value}")
    fi
done

# Execute Java with expanded arguments
exec java "${JAVA_ARGS[@]}"
