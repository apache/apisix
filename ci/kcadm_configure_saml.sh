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

kcadm.sh config credentials --server http://localhost:8080 --realm master --user admin --password admin

kcadm.sh create realms -s realm=test -s enabled=true

kcadm.sh create users -r test -s username=test -s enabled=true
kcadm.sh set-password -r test --username test --new-password test

sp_cert="MIIDgjCCAmqgAwIBAgIUOnf+MXKVU2zfIVaPz5dl0NTwPM4wDQYJKoZIhvcNAQENBQAwUTELMAkGA1UEBhMCVVMxDjAMBgNVBAgMBVRleGFzMRcwFQYDVQQKDA5sdWEtcmVzdHktc2FtbDEZMBcGA1UEAwwQc2VydmljZS1wcm92aWRlcjAgFw0xOTA1MDgwMTIyMDZaGA8yMTE4MDQxNDAxMjIwNlowUTELMAkGA1UEBhMCVVMxDjAMBgNVBAgMBVRleGFzMRcwFQYDVQQKDA5sdWEtcmVzdHktc2FtbDEZMBcGA1UEAwwQc2VydmljZS1wcm92aWRlcjCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAMLOj3YA5OGWqwV/GojID2AeuPfj3dTFOWFajXk4mc0vUBE10ovgkUfqdj2wye2Qu1ox1joFgMjaUcK/prXFBLFq+RLiR6lMUyi2PvCZ8tdYRjeYVtshNsZSZNDTJCgnguuKL+dDoSy/bTNX+ZJMnMctN1wf+Ui6Sxlcos+cTO57fOoaim+Thl26/DJHNTQXM+hJiUIuoAQlzHpuS6VBxlypIRH/RuR7+b14IO33V68MkzXI4fNi6INkfy2uEXDMT72az8j/xK+361CQAHkQDN8jbpWlRYHeirh4mygQ8QLhQkGwppmHhrUYD7BubyqXwSBSvQSyAVkfUeAaDab3ucsCAwEAAaNQME4wHQYDVR0OBBYEFPbRiK9OxGCZeNUViinNQ4P5ZOf0MB8GA1UdIwQYMBaAFPbRiK9OxGCZeNUViinNQ4P5ZOf0MAwGA1UdEwQFMAMBAf8wDQYJKoZIhvcNAQENBQADggEBAD0MvA3mk+u3CBDFwPtT9tI8HPSaYXS0HZ3EVXe4WcU3PYFpZzK0x6qr+a7mB3tbpHYXl49V7uxcIOD2aHLvKonKRRslyTiw4UvLOhSSByrArUGleI0wyr1BXAJArippiIhqrTDybvPpFC45x45/KtrckeM92NOlttlQyd2yW0qSd9gAnqkDu2kvjLlGh9ZYnT+yHPjUuWcxDL66P3za6gc+GhVOtsOemdYNAErhuxiGVNHrtq2dfSedqcxtCpavMYzyGhqzxr9Lt43fpQeXeS/7JVFoC2y9buyOz9HIbQ6/02HIoenDoP3xfqvAY1emixgbV4iwm3SWzG8pSTxvwuM="

clients=("sp" "sp2")
rootUrls=("http://127.0.0.1:1984" "http://127.0.0.2:1984")

for i in ${!clients[@]}; do
    kcadm.sh create clients -r test -s clientId=${clients[$i]} -s enabled=true

    id=$(kcadm.sh get clients -r test --fields id,clientId 2>/dev/null | jq -r '.[] | select(.clientId=='\"${clients[$i]}\"') | .id')

    kcadm.sh update clients/${id} -r test -s protocol=saml -s frontchannelLogout=true -s rootUrl=${rootUrls[$i]} -s 'redirectUris=["/acs"]' -s 'attributes={"saml.server.signature":"true", "saml.authnstatement":"true", "saml.signature.algorithm":"RSA_SHA256", "saml.client.signature":"true", "saml.force.post.binding":"false", "saml_single_logout_service_url_redirect":"/sls", "saml.signing.certificate":'\"${sp_cert}\"'}'
done
