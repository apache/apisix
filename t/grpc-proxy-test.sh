#!/usr/bin/env sh
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

set -ex

#set ssl
curl http://127.0.0.1:9180/apisix/admin/ssl/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "cert": "-----BEGIN CERTIFICATE-----\nMIIEojCCAwqgAwIBAgIJAK253pMhgCkxMA0GCSqGSIb3DQEBCwUAMFYxCzAJBgNV\nBAYTAkNOMRIwEAYDVQQIDAlHdWFuZ0RvbmcxDzANBgNVBAcMBlpodUhhaTEPMA0G\nA1UECgwGaXJlc3R5MREwDwYDVQQDDAh0ZXN0LmNvbTAgFw0xOTA2MjQyMjE4MDVa\nGA8yMTE5MDUzMTIyMTgwNVowVjELMAkGA1UEBhMCQ04xEjAQBgNVBAgMCUd1YW5n\nRG9uZzEPMA0GA1UEBwwGWmh1SGFpMQ8wDQYDVQQKDAZpcmVzdHkxETAPBgNVBAMM\nCHRlc3QuY29tMIIBojANBgkqhkiG9w0BAQEFAAOCAY8AMIIBigKCAYEAyCM0rqJe\ncvgnCfOw4fATotPwk5Ba0gC2YvIrO+gSbQkyxXF5jhZB3W6BkWUWR4oNFLLSqcVb\nVDPitz/Mt46Mo8amuS6zTbQetGnBARzPLtmVhJfoeLj0efMiOepOSZflj9Ob4yKR\n2bGdEFOdHPjm+4ggXU9jMKeLqdVvxll/JiVFBW5smPtW1Oc/BV5terhscJdOgmRr\nabf9xiIis9/qVYfyGn52u9452V0owUuwP7nZ01jt6iMWEGeQU6mwPENgvj1olji2\nWjdG2UwpUVp3jp3l7j1ekQ6mI0F7yI+LeHzfUwiyVt1TmtMWn1ztk6FfLRqwJWR/\nEvm95vnfS3Le4S2ky3XAgn2UnCMyej3wDN6qHR1onpRVeXhrBajbCRDRBMwaNw/1\n/3Uvza8QKK10PzQR6OcQ0xo9psMkd9j9ts/dTuo2fzaqpIfyUbPST4GdqNG9NyIh\n/B9g26/0EWcjyO7mYVkaycrtLMaXm1u9jyRmcQQI1cGrGwyXbrieNp63AgMBAAGj\ncTBvMB0GA1UdDgQWBBSZtSvV8mBwl0bpkvFtgyiOUUcbszAfBgNVHSMEGDAWgBSZ\ntSvV8mBwl0bpkvFtgyiOUUcbszAMBgNVHRMEBTADAQH/MB8GA1UdEQQYMBaCCHRl\nc3QuY29tggoqLnRlc3QuY29tMA0GCSqGSIb3DQEBCwUAA4IBgQAHGEul/x7ViVgC\ntC8CbXEslYEkj1XVr2Y4hXZXAXKd3W7V3TC8rqWWBbr6L/tsSVFt126V5WyRmOaY\n1A5pju8VhnkhYxYfZALQxJN2tZPFVeME9iGJ9BE1wPtpMgITX8Rt9kbNlENfAgOl\nPYzrUZN1YUQjX+X8t8/1VkSmyZysr6ngJ46/M8F16gfYXc9zFj846Z9VST0zCKob\nrJs3GtHOkS9zGGldqKKCj+Awl0jvTstI4qtS1ED92tcnJh5j/SSXCAB5FgnpKZWy\nhme45nBQj86rJ8FhN+/aQ9H9/2Ib6Q4wbpaIvf4lQdLUEcWAeZGW6Rk0JURwEog1\n7/mMgkapDglgeFx9f/XztSTrkHTaX4Obr+nYrZ2V4KOB4llZnK5GeNjDrOOJDk2y\nIJFgBOZJWyS93dQfuKEj42hA79MuX64lMSCVQSjX+ipR289GQZqFrIhiJxLyA+Ve\nU/OOcSRr39Kuis/JJ+DkgHYa/PWHZhnJQBxcqXXk1bJGw9BNbhM=\n-----END CERTIFICATE-----\n",
    "key": "-----BEGIN RSA PRIVATE KEY-----\nMIIG5AIBAAKCAYEAyCM0rqJecvgnCfOw4fATotPwk5Ba0gC2YvIrO+gSbQkyxXF5\njhZB3W6BkWUWR4oNFLLSqcVbVDPitz/Mt46Mo8amuS6zTbQetGnBARzPLtmVhJfo\neLj0efMiOepOSZflj9Ob4yKR2bGdEFOdHPjm+4ggXU9jMKeLqdVvxll/JiVFBW5s\nmPtW1Oc/BV5terhscJdOgmRrabf9xiIis9/qVYfyGn52u9452V0owUuwP7nZ01jt\n6iMWEGeQU6mwPENgvj1olji2WjdG2UwpUVp3jp3l7j1ekQ6mI0F7yI+LeHzfUwiy\nVt1TmtMWn1ztk6FfLRqwJWR/Evm95vnfS3Le4S2ky3XAgn2UnCMyej3wDN6qHR1o\nnpRVeXhrBajbCRDRBMwaNw/1/3Uvza8QKK10PzQR6OcQ0xo9psMkd9j9ts/dTuo2\nfzaqpIfyUbPST4GdqNG9NyIh/B9g26/0EWcjyO7mYVkaycrtLMaXm1u9jyRmcQQI\n1cGrGwyXbrieNp63AgMBAAECggGBAJM8g0duoHmIYoAJzbmKe4ew0C5fZtFUQNmu\nO2xJITUiLT3ga4LCkRYsdBnY+nkK8PCnViAb10KtIT+bKipoLsNWI9Xcq4Cg4G3t\n11XQMgPPgxYXA6m8t+73ldhxrcKqgvI6xVZmWlKDPn+CY/Wqj5PA476B5wEmYbNC\nGIcd1FLl3E9Qm4g4b/sVXOHARF6iSvTR+6ol4nfWKlaXSlx2gNkHuG8RVpyDsp9c\nz9zUqAdZ3QyFQhKcWWEcL6u9DLBpB/gUjyB3qWhDMe7jcCBZR1ALyRyEjmDwZzv2\njlv8qlLFfn9R29UI0pbuL1eRAz97scFOFme1s9oSU9a12YHfEd2wJOM9bqiKju8y\nDZzePhEYuTZ8qxwiPJGy7XvRYTGHAs8+iDlG4vVpA0qD++1FTpv06cg/fOdnwshE\nOJlEC0ozMvnM2rZ2oYejdG3aAnUHmSNa5tkJwXnmj/EMw1TEXf+H6+xknAkw05nh\nzsxXrbuFUe7VRfgB5ElMA/V4NsScgQKBwQDmMRtnS32UZjw4A8DsHOKFzugfWzJ8\nGc+3sTgs+4dNIAvo0sjibQ3xl01h0BB2Pr1KtkgBYB8LJW/FuYdCRS/KlXH7PHgX\n84gYWImhNhcNOL3coO8NXvd6+m+a/Z7xghbQtaraui6cDWPiCNd/sdLMZQ/7LopM\nRbM32nrgBKMOJpMok1Z6zsPzT83SjkcSxjVzgULNYEp03uf1PWmHuvjO1yELwX9/\ngoACViF+jst12RUEiEQIYwr4y637GQBy+9cCgcEA3pN9W5OjSPDVsTcVERig8++O\nBFURiUa7nXRHzKp2wT6jlMVcu8Pb2fjclxRyaMGYKZBRuXDlc/RNO3uTytGYNdC2\nIptU5N4M7iZHXj190xtDxRnYQWWo/PR6EcJj3f/tc3Itm1rX0JfuI3JzJQgDb9Z2\ns/9/ub8RRvmQV9LM/utgyOwNdf5dyVoPcTY2739X4ZzXNH+CybfNa+LWpiJIVEs2\ntxXbgZrhmlaWzwA525nZ0UlKdfktdcXeqke9eBghAoHARVTHFy6CjV7ZhlmDEtqE\nU58FBOS36O7xRDdpXwsHLnCXhbFu9du41mom0W4UdzjgVI9gUqG71+SXrKr7lTc3\ndMHcSbplxXkBJawND/Q1rzLG5JvIRHO1AGJLmRgIdl8jNgtxgV2QSkoyKlNVbM2H\nWy6ZSKM03lIj74+rcKuU3N87dX4jDuwV0sPXjzJxL7NpR/fHwgndgyPcI14y2cGz\nzMC44EyQdTw+B/YfMnoZx83xaaMNMqV6GYNnTHi0TO2TAoHBAKmdrh9WkE2qsr59\nIoHHygh7Wzez+Ewr6hfgoEK4+QzlBlX+XV/9rxIaE0jS3Sk1txadk5oFDebimuSk\nlQkv1pXUOqh+xSAwk5v88dBAfh2dnnSa8HFN3oz+ZfQYtnBcc4DR1y2X+fVNgr3i\nnxruU2gsAIPFRnmvwKPc1YIH9A6kIzqaoNt1f9VM243D6fNzkO4uztWEApBkkJgR\n4s/yOjp6ovS9JG1NMXWjXQPcwTq3sQVLnAHxZRJmOvx69UmK4QKBwFYXXjeXiU3d\nbcrPfe6qNGjfzK+BkhWznuFUMbuxyZWDYQD5yb6ukUosrj7pmZv3BxKcKCvmONU+\nCHgIXB+hG+R9S2mCcH1qBQoP/RSm+TUzS/Bl2UeuhnFZh2jSZQy3OwryUi6nhF0u\nLDzMI/6aO1ggsI23Ri0Y9ZtqVKczTkxzdQKR9xvoNBUufjimRlS80sJCEB3Qm20S\nwzarryret/7GFW1/3cz+hTj9/d45i25zArr3Pocfpur5mfz3fJO8jg==\n-----END RSA PRIVATE KEY-----\n",
    "sni": "test.com"
}'

#test grpc proxy
curl http://127.0.0.1:9180/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

echo "127.0.0.1 test.com" | sudo tee -a /etc/hosts

./build-cache/grpcurl -insecure -import-path ./build-cache/proto -proto helloworld.proto -d '{"name":"apisix"}' test.com:9443 helloworld.Greeter.SayHello


#delete test data
curl http://127.0.0.1:9180/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X DELETE
curl http://127.0.0.1:9180/apisix/admin/ssl/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X DELETE
