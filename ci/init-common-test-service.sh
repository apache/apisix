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

# prepare vault kv engine
sleep 3s
docker exec -i vault sh -c "VAULT_TOKEN='root' VAULT_ADDR='http://0.0.0.0:8200' vault secrets enable -path=kv -version=1 kv"

# prepare localstack
sleep 3s
docker exec -i localstack sh -c "awslocal secretsmanager create-secret --name apisix-key --description 'APISIX Secret' --secret-string '{\"jack\":\"value\"}'"
sleep 3s
docker exec -i localstack sh -c "awslocal secretsmanager create-secret --name apisix-mysql --description 'APISIX Secret' --secret-string 'secret'"
sleep 3s
docker exec -i localstack sh -c "awslocal secretsmanager create-secret --name apisix/string --description 'APISIX Secret' --secret-string 'secret'"
sleep 3s
docker exec -i localstack sh -c "awslocal secretsmanager create-secret --name apisix/json --description 'APISIX Secret' --secret-string '{\"jack\":\"value\"}'"
