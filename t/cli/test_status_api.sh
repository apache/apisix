#!/usr/bin/env bash

. ./t/cli/common.sh

git checkout conf/config.yaml


echo '
deployment:
  role: traditional
  role_traditional:
    config_provider: etcd
  etcd:
    host:
      - "http://127.0.0.1:23790"
      - "http://127.0.0.1:23791"
      - "http://127.0.0.1:23792"
    prefix: /apisix
nginx_config:
  error_log_level: info
apisix:
  status:
    ip: 127.0.0.1
    port: 7085
' > conf/config.yaml

# create 3 node etcd cluster in docker
ETCD_NAME_0=etcd0
ETCD_NAME_1=etcd1
ETCD_NAME_2=etcd2
docker-compose -f ./t/cli/docker-compose-etcd-cluster.yaml up -d

make run

curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:7085/status | grep 200 \
|| (echo "failed: status api didn't return 200"; exit 1)

curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:7085/status/ready | grep 200 \
|| (echo "failed: status/ready api didn't return 200"; exit 1)

# stop two etcd endpoints but status api should return 200 as one etcd endpoint is still active
docker stop ${ETCD_NAME_0}
docker stop ${ETCD_NAME_1}

curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:7085/status | grep 200 \
|| (echo "failed: status api didn't return 200"; exit 1)

curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:7085/status/ready | grep 200 \
|| (echo "failed: status/ready api didn't return 200"; exit 1)

# stop the last etcd endpoint, now status api must return 503
docker stop ${ETCD_NAME_2}

curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:7085/status/ready | grep 503 \
|| (echo "failed: status/ready api didn't return 503"; exit 1)

docker-compose -f ./t/cli/docker-compose-etcd-cluster.yaml down
