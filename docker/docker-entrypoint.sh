#!/usr/bin/env bash

set -eo pipefail

PREFIX=${APISIX_PREFIX:=/usr/local/apisix}

if [[ "$1" == "docker-start" ]]; then
    if [ "$APISIX_STAND_ALONE" = "true" ]; then
        cat > ${PREFIX}/conf/config.yaml << _EOC_
deployment:
  role: data_plane
  role_data_plane:
    config_provider: yaml
_EOC_

        cat > ${PREFIX}/conf/apisix.yaml << _EOC_
routes:
  -
#END
_EOC_
        /usr/bin/apisix init
    else
        /usr/bin/apisix init
        /usr/bin/apisix init_etcd
    fi

    exec /usr/local/openresty-debug/bin/openresty -p /usr/local/apisix -g 'daemon off;'
fi

exec "$@"