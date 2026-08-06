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
# Boot hook (docker-entrypoint-initdb.d).
#
# olcAllows bind_anon_dn: a simple bind with a DN and an EMPTY password
# succeeds at the server (RFC 4513 5.1.2, result: anonymous) -- lets the
# tests prove the plugin itself rejects empty passwords.
#
# The olcAccess rules make the bind identity observable:
#   * cn=Secret User: invisible to an anonymous search, readable by any
#     authenticated identity (userPassword keeps `auth` so the entry can
#     still be bound once found) -- the bind-state-leak tripwire.
#   * ou=groups `member`: readable by anonymous (the group-search identity)
#     but NOT by end users -- a group search that skipped the re-bind would
#     match nothing. The rootdn (cn=admin) bypasses ACLs entirely.
#   * The catch-all keeps everything else readable, so the ldap-auth
#     regression and the memberOf attribute are unaffected.

set -o errexit
set -o nounset
set -o pipefail

. /opt/bitnami/scripts/liblog.sh
. /opt/bitnami/scripts/libopenldap.sh

eval "$(ldap_env)"

info "Enabling RFC 4513 unauthenticated bind (olcAllows: bind_anon_dn)"

ldap_start_bg

ldapmodify -Y EXTERNAL -H "ldapi:///" <<EOF
dn: cn=config
changetype: modify
add: olcAllows
olcAllows: bind_anon_dn
EOF

info "Installing the bind-identity olcAccess rules on the data database"

# Resolve the data database DN by suffix so we do not hard-code the {N} index.
DATA_DB_DN="$(ldapsearch -Y EXTERNAL -H "ldapi:///" -b cn=config \
    "(olcSuffix=dc=example,dc=org)" dn 2>/dev/null \
    | awk '/^dn:/ { $1=""; sub(/^ /,""); print; exit }')"

if [ -z "${DATA_DB_DN}" ]; then
    error "cannot resolve the cn=config database DN for suffix dc=example,dc=org"
    exit 1
fi

ldapmodify -Y EXTERNAL -H "ldapi:///" <<EOF
dn: ${DATA_DB_DN}
changetype: modify
replace: olcAccess
olcAccess: {0}to dn.exact="cn=Secret User,ou=users,dc=example,dc=org" attrs=userPassword by anonymous auth by users read by * none
olcAccess: {1}to dn.exact="cn=Secret User,ou=users,dc=example,dc=org" by users read by * none
olcAccess: {2}to dn.subtree="ou=groups,dc=example,dc=org" attrs=member by anonymous read by users none
olcAccess: {3}to * by * read
EOF

ldap_stop
