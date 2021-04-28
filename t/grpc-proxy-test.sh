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

clean_up() {
    #delete test data
    curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X DELETE
    curl http://127.0.0.1:9080/apisix/admin/ssl/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X DELETE
}

set -ex

# ensure grpc server example is already started
for (( i = 0; i <= 100; i++ )); do
    if [[ "$i" -eq 100 ]]; then
        echo "failed to start grpc_server_example in time"
        exit 1
    fi
    nc -zv 127.0.0.1 50051 && break
    sleep 1
done

#set ssl
curl http://127.0.0.1:9080/apisix/admin/ssl/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "cert": "-----BEGIN CERTIFICATE-----\nMIIEojCCAwqgAwIBAgIJAK253pMhgCkxMA0GCSqGSIb3DQEBCwUAMFYxCzAJBgNV\nBAYTAkNOMRIwEAYDVQQIDAlHdWFuZ0RvbmcxDzANBgNVBAcMBlpodUhhaTEPMA0G\nA1UECgwGaXJlc3R5MREwDwYDVQQDDAh0ZXN0LmNvbTAgFw0xOTA2MjQyMjE4MDVa\nGA8yMTE5MDUzMTIyMTgwNVowVjELMAkGA1UEBhMCQ04xEjAQBgNVBAgMCUd1YW5n\nRG9uZzEPMA0GA1UEBwwGWmh1SGFpMQ8wDQYDVQQKDAZpcmVzdHkxETAPBgNVBAMM\nCHRlc3QuY29tMIIBojANBgkqhkiG9w0BAQEFAAOCAY8AMIIBigKCAYEAyCM0rqJe\ncvgnCfOw4fATotPwk5Ba0gC2YvIrO+gSbQkyxXF5jhZB3W6BkWUWR4oNFLLSqcVb\nVDPitz/Mt46Mo8amuS6zTbQetGnBARzPLtmVhJfoeLj0efMiOepOSZflj9Ob4yKR\n2bGdEFOdHPjm+4ggXU9jMKeLqdVvxll/JiVFBW5smPtW1Oc/BV5terhscJdOgmRr\nabf9xiIis9/qVYfyGn52u9452V0owUuwP7nZ01jt6iMWEGeQU6mwPENgvj1olji2\nWjdG2UwpUVp3jp3l7j1ekQ6mI0F7yI+LeHzfUwiyVt1TmtMWn1ztk6FfLRqwJWR/\nEvm95vnfS3Le4S2ky3XAgn2UnCMyej3wDN6qHR1onpRVeXhrBajbCRDRBMwaNw/1\n/3Uvza8QKK10PzQR6OcQ0xo9psMkd9j9ts/dTuo2fzaqpIfyUbPST4GdqNG9NyIh\n/B9g26/0EWcjyO7mYVkaycrtLMaXm1u9jyRmcQQI1cGrGwyXbrieNp63AgMBAAGj\ncTBvMB0GA1UdDgQWBBSZtSvV8mBwl0bpkvFtgyiOUUcbszAfBgNVHSMEGDAWgBSZ\ntSvV8mBwl0bpkvFtgyiOUUcbszAMBgNVHRMEBTADAQH/MB8GA1UdEQQYMBaCCHRl\nc3QuY29tggoqLnRlc3QuY29tMA0GCSqGSIb3DQEBCwUAA4IBgQAHGEul/x7ViVgC\ntC8CbXEslYEkj1XVr2Y4hXZXAXKd3W7V3TC8rqWWBbr6L/tsSVFt126V5WyRmOaY\n1A5pju8VhnkhYxYfZALQxJN2tZPFVeME9iGJ9BE1wPtpMgITX8Rt9kbNlENfAgOl\nPYzrUZN1YUQjX+X8t8/1VkSmyZysr6ngJ46/M8F16gfYXc9zFj846Z9VST0zCKob\nrJs3GtHOkS9zGGldqKKCj+Awl0jvTstI4qtS1ED92tcnJh5j/SSXCAB5FgnpKZWy\nhme45nBQj86rJ8FhN+/aQ9H9/2Ib6Q4wbpaIvf4lQdLUEcWAeZGW6Rk0JURwEog1\n7/mMgkapDglgeFx9f/XztSTrkHTaX4Obr+nYrZ2V4KOB4llZnK5GeNjDrOOJDk2y\nIJFgBOZJWyS93dQfuKEj42hA79MuX64lMSCVQSjX+ipR289GQZqFrIhiJxLyA+Ve\nU/OOcSRr39Kuis/JJ+DkgHYa/PWHZhnJQBxcqXXk1bJGw9BNbhM=\n-----END CERTIFICATE-----\n",
    "key": "-----BEGIN RSA PRIVATE KEY-----\n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\n-----END RSA PRIVATE KEY-----\n",
    "sni": "test.com"
}'

#test grpc proxy
curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["POST"],
    "uri": "/helloworld.Greeter/SayHello",
    "upstream": {
        "scheme": "grpc",
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:50051": 1
        }
    }
}'

# test grpc proxy with plaintext
./build-cache/grpcurl -plaintext -import-path ./build-cache/proto -proto helloworld.proto -d '{"name":"apisix"}' 127.0.0.1:9081 helloworld.Greeter.SayHello | grep 'Hello apisix'

# test grpc proxy with ssl
./build-cache/grpcurl -insecure -import-path ./build-cache/proto -proto helloworld.proto -d '{"name":"apisix"}' test.com:9443 helloworld.Greeter.SayHello | grep 'Hello apisix'

# the old way
curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["POST"],
    "uri": "/helloworld.Greeter/SayHello",
    "service_protocol": "grpc",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:50051": 1
        }
    }
}'

./build-cache/grpcurl -insecure -import-path ./build-cache/proto -proto helloworld.proto -d '{"name":"apisix"}' test.com:9443 helloworld.Greeter.SayHello | grep 'Hello apisix'

#test grpcs proxy
curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["POST"],
    "uri": "/helloworld.Greeter/SayHello",
    "upstream": {
        "scheme": "grpcs",
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:50052": 1
        }
    }
}'

./build-cache/grpcurl -insecure -import-path ./build-cache/proto -proto helloworld.proto -d '{"name":"apisix"}' test.com:9443 helloworld.Greeter.SayHello | grep 'Hello apisix'

if ! openresty -V 2>&1 | grep "apisix-nginx-module"; then
    echo "skip vanilla OpenResty"
    clean_up
    exit 0
fi

#test grpcs with mTLS proxy
curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["POST"],
    "uri": "/helloworld.Greeter/SayHello",
    "upstream": {
        "scheme": "grpcs",
        "tls": {
            "client_cert": "-----BEGIN CERTIFICATE-----\nMIIDOjCCAiICAwD6zzANBgkqhkiG9w0BAQsFADBnMQswCQYDVQQGEwJjbjESMBAG\nA1UECAwJR3VhbmdEb25nMQ8wDQYDVQQHDAZaaHVIYWkxDTALBgNVBAoMBGFwaTcx\nDDAKBgNVBAsMA29wczEWMBQGA1UEAwwNY2EuYXBpc2l4LmRldjAeFw0yMDA2MjAx\nMzE1MDBaFw0zMDA3MDgxMzE1MDBaMF0xCzAJBgNVBAYTAmNuMRIwEAYDVQQIDAlH\ndWFuZ0RvbmcxDTALBgNVBAoMBGFwaTcxDzANBgNVBAcMBlpodUhhaTEaMBgGA1UE\nAwwRY2xpZW50LmFwaXNpeC5kZXYwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEK\nAoIBAQCfKI8uiEH/ifZikSnRa3/E2B4ohVWRwjo/IxyDEWomgR4tLk1pSJhP/4SC\nLWuMQTFWTbSqt1IFYy4ZbVSHHyGoNPmJGrHRJCGE+sgpfzn0GjV4lXQPJD0k6GR1\nCX2Mo1TWdFqSJ/Hc5AQwcQFnPfoLAwsBy4yqrlmf96ZAUytl/7Zkjf4P7mJkJHtM\n/WgSR0pGhjZTAGRf5DJWoO51ki3i3JI+15mOhmnnCpnksnGVPfl92q92Hz/4v3iq\nE+UThPYRpcGbnddzMvPaCXiavg8B/u2LVbn4l0adamqQGepOAjD/1xraOVP2W22W\n0PztDXJ4rLe+capNS4oGuSUfkIENAgMBAAEwDQYJKoZIhvcNAQELBQADggEBAHKn\nHxUhuk/nL2Sg5UB84OoJe5XPgNBvVMKN0c/NAPKVIPninvUcG/mHeKexPzE0sMga\nRNos75N2199EXydqUcsJ8jL0cNtQ2k5JQXXg0ntNC4tuCgIKAOnO879y5hSG36e5\n7wmAoVKnabgjej09zG1kkXvAmpgqoxeVCu7h7fK+AurLbsGCTaHoA5pG1tcHDxJQ\nfpVcbBfwQDSBW3SQjiRqX453/01nw6kbOeLKYraJysaG8ZU2K8+WpW6JDubciHjw\nfQnpU2U16XKivhxeuKYrV/INL0sxj/fZraNYErvJWzh5llvIdNLmeSPmvb50JUIs\n+lDqn1MobTXzDpuCFXA=\n-----END CERTIFICATE-----\n",
            "client_key": "-----BEGIN RSA PRIVATE KEY-----\nMIIEpAIBAAKCAQEAnyiPLohB/4n2YpEp0Wt/xNgeKIVVkcI6PyMcgxFqJoEeLS5N\naUiYT/+Egi1rjEExVk20qrdSBWMuGW1Uhx8hqDT5iRqx0SQhhPrIKX859Bo1eJV0\nDyQ9JOhkdQl9jKNU1nRakifx3OQEMHEBZz36CwMLAcuMqq5Zn/emQFMrZf+2ZI3+\nD+5iZCR7TP1oEkdKRoY2UwBkX+QyVqDudZIt4tySPteZjoZp5wqZ5LJxlT35fdqv\ndh8/+L94qhPlE4T2EaXBm53XczLz2gl4mr4PAf7ti1W5+JdGnWpqkBnqTgIw/9ca\n2jlT9lttltD87Q1yeKy3vnGqTUuKBrklH5CBDQIDAQABAoIBAHDe5bPdQ9jCcW3z\nfpGax/DER5b6//UvpfkSoGy/E+Wcmdb2yEVLC2FoVwOuzF+Z+DA5SU/sVAmoDZBQ\nvapZxJeygejeeo5ULkVNSFhNdr8LOzJ54uW+EHK1MFDj2xq61jaEK5sNIvRA7Eui\nSJl8FXBrxwmN3gNJRBwzF770fImHUfZt0YU3rWKw5Qin7QnlUzW2KPUltnSEq/xB\nkIzyWpuj7iAm9wTjH9Vy06sWCmxj1lzTTXlanjPb1jOTaOhbQMpyaAzRgQN8PZiE\nYKCarzVj7BJr7/vZYpnQtQDY12UL5n33BEqMP0VNHVqv+ZO3bktfvlwBru5ZJ7Cf\nURLsSc0CgYEAyz7FzV7cZYgjfUFD67MIS1HtVk7SX0UiYCsrGy8zA19tkhe3XVpc\nCZSwkjzjdEk0zEwiNAtawrDlR1m2kverbhhCHqXUOHwEpujMBjeJCNUVEh3OABr8\nvf2WJ6D1IRh8FA5CYLZP7aZ41fcxAnvIPAEThemLQL3C4H5H5NG2WFsCgYEAyHhP\nonpS/Eo/OXKYFLR/mvjizRVSomz1lVVL+GWMUYQsmgsPyBJgyAOX3Pqt9catgxhM\nDbEr7EWTxth3YeVzamiJPNVK0HvCax9gQ0KkOmtbrfN54zBHOJ+ieYhsieZLMgjx\niu7Ieo6LDGV39HkvekzutZpypiCpKlMaFlCFiLcCgYEAmAgRsEj4Nh665VPvuZzH\nZIgZMAlwBgHR7/v6l7AbybcVYEXLTNJtrGEEH6/aOL8V9ogwwZuIvb/TEidCkfcf\nzg/pTcGf2My0MiJLk47xO6EgzNdso9mMG5ZYPraBBsuo7NupvWxCp7NyCiOJDqGH\nK5NmhjInjzsjTghIQRq5+qcCgYEAxnm/NjjvslL8F69p/I3cDJ2/RpaG0sMXvbrO\nVWaMryQyWGz9OfNgGIbeMu2Jj90dar6ChcfUmb8lGOi2AZl/VGmc/jqaMKFnElHl\nJ5JyMFicUzPMiG8DBH+gB71W4Iy+BBKwugHBQP2hkytewQ++PtKuP+RjADEz6vCN\n0mv0WS8CgYBnbMRP8wIOLJPRMw/iL9BdMf606X4xbmNn9HWVp2mH9D3D51kDFvls\n7y2vEaYkFv3XoYgVN9ZHDUbM/YTUozKjcAcvz0syLQb8wRwKeo+XSmo09+360r18\nzRugoE7bPl39WdGWaW3td0qf1r9z3sE2iWUTJPRQ3DYpsLOYIgyKmw==\n-----END RSA PRIVATE KEY-----\n"
        },
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:50053": 1
        }
    }
}'

./build-cache/grpcurl -insecure -import-path ./build-cache/proto -proto helloworld.proto -d '{"name":"apisix"}' test.com:9443 helloworld.Greeter.SayHello | grep 'Hello apisix'
clean_up
