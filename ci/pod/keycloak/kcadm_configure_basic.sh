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

export PATH=/opt/keycloak/bin:$PATH

kcadm.sh config credentials --server http://127.0.0.1:8080 --realm master --user admin --password admin

# create realm
kcadm.sh create realms -s realm=basic -s enabled=true

# set realm keys with specific private key, reuse tls cert and key
PRIVATE_KEY=$(awk 'NF {sub(/\r/, ""); printf "%s\\n", $0}' /opt/keycloak/conf/server.key.pem)
CERTIFICATE=$(awk 'NF {sub(/\r/, ""); printf "%s\\n", $0}' /opt/keycloak/conf/server.crt.pem)
kcadm.sh create components -r basic -s name=rsa-apisix -s providerId=rsa \
    -s providerType=org.keycloak.keys.KeyProvider \
    -s 'config.priority=["1000"]' \
    -s 'config.enabled=["true"]' \
    -s 'config.active=["true"]' \
    -s "config.privateKey=[\"$PRIVATE_KEY\"]" \
    -s "config.certificate=[\"$CERTIFICATE\"]" \
    -s 'config.algorithm=["RS256"]'

# create client apisix
kcadm.sh create clients \
    -r basic \
    -s clientId=apisix \
    -s enabled=true \
    -s clientAuthenticatorType=client-secret \
    -s secret=secret \
    -s 'redirectUris=["*"]' \
    -s 'directAccessGrantsEnabled=true'

# add audience to client apisix, so that the access token will contain the client id ("apisix") as audience 
APISIX_CLIENT_UUID=$(kcadm.sh get clients -r basic -q clientId=apisix | jq -r '.[0].id')
kcadm.sh create clients/$APISIX_CLIENT_UUID/protocol-mappers/models \
  -r basic \
  -s protocol=openid-connect \
  -s name=aud \
  -s protocolMapper=oidc-audience-mapper \
  -s 'config."id.token.claim"=false' \
  -s 'config."access.token.claim"=true' \
  -s 'config."included.client.audience"=apisix'

# create client apisix
kcadm.sh create clients \
    -r basic \
    -s clientId=apisix \
    -s enabled=true \
    -s clientAuthenticatorType=client-secret \
    -s secret=secret \
    -s 'redirectUris=["*"]' \
    -s 'directAccessGrantsEnabled=true'

# create client apisix-no-aud, without client id audience
# according to Keycloak's default implementation, when unconfigured,
# only the account is listed as an audience, not the client id

kcadm.sh create clients \
    -r basic \
    -s clientId=apisix-no-aud \
    -s enabled=true \
    -s clientAuthenticatorType=client-secret \
    -s secret=secret \
    -s 'redirectUris=["*"]' \
    -s 'directAccessGrantsEnabled=true'

# create user jack
kcadm.sh create users -r basic -s username=jack -s enabled=true
kcadm.sh set-password -r basic --username jack --new-password jack
