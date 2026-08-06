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
# Boot hook (docker-entrypoint-initdb.d): activates the memberof overlay,
# THEN loads the groups. The overlay only back-populates memberOf for member
# links added after it is active, so the groups cannot live in /ldifs.

set -o errexit
set -o nounset
set -o pipefail

. /opt/bitnami/scripts/liblog.sh
. /opt/bitnami/scripts/libopenldap.sh

eval "$(ldap_env)"

ldap_start_bg

info "Activating the memberof + refint overlays"

ldapadd -Y EXTERNAL -H "ldapi:///" -f /overlays/memberof.ldif

info "Loading authorization groups (overlay back-populates memberOf)"

ldapadd -H "ldapi:///" -D "$LDAP_ADMIN_DN" -w "$LDAP_ADMIN_PASSWORD" -f /overlays/groups.ldif

ldap_stop
