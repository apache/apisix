#!/bin/bash
#set -ex

# nacos server healthcheck
REQ_STATUS=$(curl -s -o /dev/null -w '%{http_code}' "${CHECK_URI}")

if [ "${REQ_STATUS}" -ne "200" ]; then
  exit 1;
fi
