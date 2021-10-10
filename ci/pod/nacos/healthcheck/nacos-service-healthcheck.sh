#!/bin/bash
#set -ex

# nacos service healthcheck
URI_LIST=(
  "http://nacos2:8848/nacos/v1/ns/service/list?pageNo=1&pageSize=2"
  "http://nacos2:8848/nacos/v1/ns/service/list?groupName=test_group&pageNo=1&pageSize=2"
  "http://nacos2:8848/nacos/v1/ns/service/list?groupName=DEFAULT_GROUP&namespaceId=test_ns&pageNo=1&pageSize=2"
  "http://nacos2:8848/nacos/v1/ns/service/list?groupName=test_group&namespaceId=test_ns&pageNo=1&pageSize=2"
)

for URI in "${URI_LIST[@]}"; do
  if [[ $(curl -s "${URI}" | grep "APISIX-NACOS") ]]; then
    continue
  else
    exit 1;
  fi
done


for IDX in {1..7..1}; do
  REQ_STATUS=$(curl -s -o /dev/null -w '%{http_code}' "http://nacos-service${IDX}:18001/hello")
  if [ "${REQ_STATUS}" -ne "200" ]; then
    exit 1;
  fi
done
