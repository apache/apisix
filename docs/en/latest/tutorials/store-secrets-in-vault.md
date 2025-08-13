---
title: Store secrets in Vault
keywords:
  - API Gateway
  - Apache APISIX
  - Vault
description: This tutorial explains how to manage your single or multiple API consumers with Apache APISIX and store its secrets in a Vault.
---

<!--
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
-->

This tutorial explains how to manage your single or multiple API consumers with Apache APISIX and store its secrets in a Vault.
Make sure you've read the [Manage API Consumers](./manage-api-consumers.md) page before.

:::

## get the example code

Get the example code from the git repository

``` shell
git clone https://github.com/apache/apisix-docker.git
cd apisix-docker/example
```

## start containers

add to the file docker-compose.yaml the following content in order to add an openbao container


``` yaml
  openbao:
    image: openbao/openbao:latest
    container_name: openbao
    ports:
      - "8200:8200/tcp" # OpenBao HTTP API
      - "8201:8201/tcp" # OpenBao HTTPS API (if configured)
    environment:
      # OpenBao specific environment variables
      # Adjust these for your needs. This is for dev mode for simplicity.
      - 'VAULT_DEV_ROOT_TOKEN_ID=myroottoken' # Only for dev mode!
      - 'VAULT_DEV_LISTEN_ADDRESS=0.0.0.0:8200'
      - 'VAULT_ADDR=http://0.0.0.0:8200' # For internal container comms
      - 'VAULT_LOG_LEVEL=debug'
    volumes:
      - ./bao_data:/vault/file # Persist data (replace with appropriate storage backend if not file)
      - ./bao_config:/vault/config # Mount custom config
    command: "server -dev"
    cap_add:
      - IPC_LOCK # Required for mlock to secure memory
    networks:
      apisix:
```

and then start the containers

``` shell
docker compose up
```

## get the API administration key
Get the secret to administrate ApiSix
``` shell
ADMIN_API_KEY=$(yq '.deployment.admin.admin_key[0].key' apisix_conf/config.yaml | sed 's/"//g')
echo $ADMIN_API_KEY
```

## create a backend (upstream)
Create a backend, in this case pointing to http://httpbin.org
``` shell
curl -i "http://127.0.0.1:9180/apisix/admin/upstreams/httpbin" -X PUT \
  -H "X-API-KEY: $ADMIN_API_KEY" \
  -d '{
    "type": "roundrobin",
    "nodes": {
      "httpbin.org:80": 1
    }
  }'
```

## create a route forwarding to the backend
Create a route, note the use of the proxy-rewrite plugin to remove the prefix '/my-secured-api/' when calling the service behind

``` shell
curl -i "http://127.0.0.1:9180/apisix/admin/routes/my-secured-route" -X PUT \
  -H "X-API-KEY: $ADMIN_API_KEY" \
  -d '{
    "uri": "/my-secured-api/*",
    "methods": ["GET"],
    "upstream_id": "httpbin",
    "plugins": {
      "key-auth": {
        "hide_credentials": true
      },
      "proxy-rewrite": {
         "regex_uri": [
           "^/my-secured-api/(.*)$",
           "/$1"
         ]
      }
    }
  }'
```

## get the root token for Openbao

Get the Openbao root token, this is only for development, in production a specific non root token with limited permissions must be used.

``` shell
docker compose logs openbao | grep "Root Token:"
```

## create the secret in openbao

The openbao path must be V1 (for the moment this is the expected version for ApiSix).

``` shell
docker exec -it openbao sh
vault login <root token>
vault secrets enable -version=1 -path=kv1_secrets kv
vault kv put kv1_secrets/apisix/my_api_key value="super_secret_key_123"
```

## create the openbao secret with the data to connect and the token

This command tells ApiSix how to connect to Openbao

``` shell
curl -i "http://127.0.0.1:9180/apisix/admin/secrets/vault/openbao_secrets" \
  -H "X-API-KEY: $ADMIN_API_KEY" \
  -X PUT -d '{
    "uri": "http://openbao:8200",
    "token": "<root token du vault>",
    "prefix": "kv1_secrets/apisix"
  }'
```

## get all the secrets

Verify your secret has been created

``` shell
curl -i "http://127.0.0.1:9180/apisix/admin/secrets/openbao_secrets"   -H "X-API-KEY: $ADMIN_API_KEY"
```

## create a consumer for openbao
``` shell
curl -i http://127.0.0.1:9180/apisix/admin/consumers/test_bao_consumer \
  -H "X-API-KEY: $ADMIN_API_KEY" \
  -X PUT -d '{
    "username": "test_bao_consumer",
    "plugins": {
        "key-auth": {
            "key": "$secret://vault/openbao_secrets/my_api_key/value"
        }
    }
}'
```

## call the backend through ApiSix
``` shell
curl -i "http://127.0.0.1:9080/my-secured-api/get"   -H 'apikey: super_secret_key_123'
```

a 200 http code is expected here


## get all routes

``` shell
curl -s "http://127.0.0.1:9180/apisix/admin/routes"   -H "X-API-KEY: $ADMIN_API_KEY" | python3 -m json.tool
```

## get all consumers

``` shell
curl -s "http://127.0.0.1:9180/apisix/admin/consumers"   -H "X-API-KEY: $ADMIN_API_KEY"
```

## dispose the full environment, together with data

data are stored in the __etcd__ container

``` shell
docker compose down --volumes
```

