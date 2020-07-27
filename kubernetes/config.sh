#!/bin/sh

export etcd_url='http://$ETCD_IP_ADDRESS:2379'

wget https://raw.githubusercontent.com/apache/incubator-apisix/master/conf/config.yaml

sed -i -e ':a' -e 'N' -e '$!ba' -e "s/allow_admin[a-z: #\/._]*\n\( *- [0-9a-zA-Z: #\/._',]*\n*\)*//g" config.yaml

sed -i -e "s%http://[0-9.]*:2379%`echo $etcd_url`%g" config.yaml

sed -i -e '/#CONFIG_YAML#/{r config.yaml' -e 'd}' apisix-gw-config-cm.yaml

