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

# validate the config.yaml

. ./t/cli/common.sh

# test proxy_ssl_trusted_certificate success
git checkout conf/config.yaml

exit_if_not_customed_nginx

echo '
apisix:
  ssl:
    ssl_trusted_certificate: t/certs/apisix.crt
nginx_config:
  http_configuration_snippet: |
    server {
        listen 1983 ssl;
        server_name test.com;
        ssl_certificate             ../t/certs/apisix.crt;
        ssl_certificate_key         ../t/certs/apisix.key;
        location /hello {
            return 200 "hello world";
        }
    }
  http_server_configuration_snippet: |
    proxy_ssl_verify on;
' > conf/config.yaml

rm logs/error.log || true
make init
make run
sleep 0.1

curl -k -i http://127.0.0.1:9180/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/hello",
    "upstream": {
        "pass_host": "rewrite",
        "nodes": {
            "127.0.0.1:1983": 1
        },
        "scheme": "https",
        "hash_on": "vars",
        "upstream_host": "test.com",
        "type": "roundrobin",
        "tls": {
            "client_cert": "-----BEGIN CERTIFICATE-----\nMIIEojCCAwqgAwIBAgIJAK253pMhgCkxMA0GCSqGSIb3DQEBCwUAMFYxCzAJBgNV\nBAYTAkNOMRIwEAYDVQQIDAlHdWFuZ0RvbmcxDzANBgNVBAcMBlpodUhhaTEPMA0G\nA1UECgwGaXJlc3R5MREwDwYDVQQDDAh0ZXN0LmNvbTAgFw0xOTA2MjQyMjE4MDVa\nGA8yMTE5MDUzMTIyMTgwNVowVjELMAkGA1UEBhMCQ04xEjAQBgNVBAgMCUd1YW5n\nRG9uZzEPMA0GA1UEBwwGWmh1SGFpMQ8wDQYDVQQKDAZpcmVzdHkxETAPBgNVBAMM\nCHRlc3QuY29tMIIBojANBgkqhkiG9w0BAQEFAAOCAY8AMIIBigKCAYEAyCM0rqJe\ncvgnCfOw4fATotPwk5Ba0gC2YvIrO+gSbQkyxXF5jhZB3W6BkWUWR4oNFLLSqcVb\nVDPitz/Mt46Mo8amuS6zTbQetGnBARzPLtmVhJfoeLj0efMiOepOSZflj9Ob4yKR\n2bGdEFOdHPjm+4ggXU9jMKeLqdVvxll/JiVFBW5smPtW1Oc/BV5terhscJdOgmRr\nabf9xiIis9/qVYfyGn52u9452V0owUuwP7nZ01jt6iMWEGeQU6mwPENgvj1olji2\nWjdG2UwpUVp3jp3l7j1ekQ6mI0F7yI+LeHzfUwiyVt1TmtMWn1ztk6FfLRqwJWR/\nEvm95vnfS3Le4S2ky3XAgn2UnCMyej3wDN6qHR1onpRVeXhrBajbCRDRBMwaNw/1\n/3Uvza8QKK10PzQR6OcQ0xo9psMkd9j9ts/dTuo2fzaqpIfyUbPST4GdqNG9NyIh\n/B9g26/0EWcjyO7mYVkaycrtLMaXm1u9jyRmcQQI1cGrGwyXbrieNp63AgMBAAGj\ncTBvMB0GA1UdDgQWBBSZtSvV8mBwl0bpkvFtgyiOUUcbszAfBgNVHSMEGDAWgBSZ\ntSvV8mBwl0bpkvFtgyiOUUcbszAMBgNVHRMEBTADAQH/MB8GA1UdEQQYMBaCCHRl\nc3QuY29tggoqLnRlc3QuY29tMA0GCSqGSIb3DQEBCwUAA4IBgQAHGEul/x7ViVgC\ntC8CbXEslYEkj1XVr2Y4hXZXAXKd3W7V3TC8rqWWBbr6L/tsSVFt126V5WyRmOaY\n1A5pju8VhnkhYxYfZALQxJN2tZPFVeME9iGJ9BE1wPtpMgITX8Rt9kbNlENfAgOl\nPYzrUZN1YUQjX+X8t8/1VkSmyZysr6ngJ46/M8F16gfYXc9zFj846Z9VST0zCKob\nrJs3GtHOkS9zGGldqKKCj+Awl0jvTstI4qtS1ED92tcnJh5j/SSXCAB5FgnpKZWy\nhme45nBQj86rJ8FhN+/aQ9H9/2Ib6Q4wbpaIvf4lQdLUEcWAeZGW6Rk0JURwEog1\n7/mMgkapDglgeFx9f/XztSTrkHTaX4Obr+nYrZ2V4KOB4llZnK5GeNjDrOOJDk2y\nIJFgBOZJWyS93dQfuKEj42hA79MuX64lMSCVQSjX+ipR289GQZqFrIhiJxLyA+Ve\nU/OOcSRr39Kuis/JJ+DkgHYa/PWHZhnJQBxcqXXk1bJGw9BNbhM=\n-----END CERTIFICATE-----\n",
            "client_key": "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"
        }
    }
}'

sleep 1

code=$(curl -v -k -i -m 20 -o /dev/null -s -w %{http_code} http://127.0.0.1:9080/hello)

if [ ! $code -eq 200 ]; then
    echo "failed: connection to upstream with mTLS failed"
    exit 1
fi

sleep 0.1

make stop

echo "passed: connection to upstream with mTLS success"

# test proxy_ssl_trusted_certificate and use incorrect ca cert
echo '
apisix:
  ssl:
    ssl_trusted_certificate: t/certs/apisix_ecc.crt
nginx_config:
  http_configuration_snippet: |
    server {
        listen 1983 ssl;
        server_name test.com;
        ssl_certificate             ../t/certs/apisix.crt;
        ssl_certificate_key         ../t/certs/apisix.key;
        location /hello {
            return 200 "hello world";
        }
    }
  http_server_configuration_snippet: |
    proxy_ssl_verify on;
' > conf/config.yaml

rm logs/error.log || true
make init
make run
sleep 0.1

curl -k -i http://127.0.0.1:9180/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/hello",
    "upstream": {
        "pass_host": "rewrite",
        "nodes": {
            "127.0.0.1:1983": 1
        },
        "scheme": "https",
        "hash_on": "vars",
        "upstream_host": "test.com",
        "type": "roundrobin",
        "tls": {
            "client_cert": "-----BEGIN CERTIFICATE-----\nMIIEojCCAwqgAwIBAgIJAK253pMhgCkxMA0GCSqGSIb3DQEBCwUAMFYxCzAJBgNV\nBAYTAkNOMRIwEAYDVQQIDAlHdWFuZ0RvbmcxDzANBgNVBAcMBlpodUhhaTEPMA0G\nA1UECgwGaXJlc3R5MREwDwYDVQQDDAh0ZXN0LmNvbTAgFw0xOTA2MjQyMjE4MDVa\nGA8yMTE5MDUzMTIyMTgwNVowVjELMAkGA1UEBhMCQ04xEjAQBgNVBAgMCUd1YW5n\nRG9uZzEPMA0GA1UEBwwGWmh1SGFpMQ8wDQYDVQQKDAZpcmVzdHkxETAPBgNVBAMM\nCHRlc3QuY29tMIIBojANBgkqhkiG9w0BAQEFAAOCAY8AMIIBigKCAYEAyCM0rqJe\ncvgnCfOw4fATotPwk5Ba0gC2YvIrO+gSbQkyxXF5jhZB3W6BkWUWR4oNFLLSqcVb\nVDPitz/Mt46Mo8amuS6zTbQetGnBARzPLtmVhJfoeLj0efMiOepOSZflj9Ob4yKR\n2bGdEFOdHPjm+4ggXU9jMKeLqdVvxll/JiVFBW5smPtW1Oc/BV5terhscJdOgmRr\nabf9xiIis9/qVYfyGn52u9452V0owUuwP7nZ01jt6iMWEGeQU6mwPENgvj1olji2\nWjdG2UwpUVp3jp3l7j1ekQ6mI0F7yI+LeHzfUwiyVt1TmtMWn1ztk6FfLRqwJWR/\nEvm95vnfS3Le4S2ky3XAgn2UnCMyej3wDN6qHR1onpRVeXhrBajbCRDRBMwaNw/1\n/3Uvza8QKK10PzQR6OcQ0xo9psMkd9j9ts/dTuo2fzaqpIfyUbPST4GdqNG9NyIh\n/B9g26/0EWcjyO7mYVkaycrtLMaXm1u9jyRmcQQI1cGrGwyXbrieNp63AgMBAAGj\ncTBvMB0GA1UdDgQWBBSZtSvV8mBwl0bpkvFtgyiOUUcbszAfBgNVHSMEGDAWgBSZ\ntSvV8mBwl0bpkvFtgyiOUUcbszAMBgNVHRMEBTADAQH/MB8GA1UdEQQYMBaCCHRl\nc3QuY29tggoqLnRlc3QuY29tMA0GCSqGSIb3DQEBCwUAA4IBgQAHGEul/x7ViVgC\ntC8CbXEslYEkj1XVr2Y4hXZXAXKd3W7V3TC8rqWWBbr6L/tsSVFt126V5WyRmOaY\n1A5pju8VhnkhYxYfZALQxJN2tZPFVeME9iGJ9BE1wPtpMgITX8Rt9kbNlENfAgOl\nPYzrUZN1YUQjX+X8t8/1VkSmyZysr6ngJ46/M8F16gfYXc9zFj846Z9VST0zCKob\nrJs3GtHOkS9zGGldqKKCj+Awl0jvTstI4qtS1ED92tcnJh5j/SSXCAB5FgnpKZWy\nhme45nBQj86rJ8FhN+/aQ9H9/2Ib6Q4wbpaIvf4lQdLUEcWAeZGW6Rk0JURwEog1\n7/mMgkapDglgeFx9f/XztSTrkHTaX4Obr+nYrZ2V4KOB4llZnK5GeNjDrOOJDk2y\nIJFgBOZJWyS93dQfuKEj42hA79MuX64lMSCVQSjX+ipR289GQZqFrIhiJxLyA+Ve\nU/OOcSRr39Kuis/JJ+DkgHYa/PWHZhnJQBxcqXXk1bJGw9BNbhM=\n-----END CERTIFICATE-----\n",
            "client_key": "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"
        }
    }
}'

sleep 0.1

code=$(curl -v -k -i -m 20 -o /dev/null -s -w %{http_code} http://127.0.0.1:9080/hello)

if [ ! $code -eq 502 ]; then
    echo "failed: should fail when proxy_ssl_verify is enabled and ssl_trusted_certificate is wrong ca cert"
    exit 1
fi

sleep 0.1

make stop

if ! grep -E 'self-signed certificate' logs/error.log; then
    echo "failed: should got 'self-signed certificate' when ssl_trusted_certificate is wrong ca cert"
    exit 1
fi

echo "passed: when proxy_ssl_verify is enabled and ssl_trusted_certificate is wrong ca cert, got 502"
