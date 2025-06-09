if ! grep -q 'role: data_plane' "${PREFIX}/conf/config.yaml"; then
    echo "Error: ${PREFIX}/conf/config.yaml does not contain 'role: data_plane'. Deployment role must be set to 'data_plane' for standalone mode."
    echo "Please refer to the APISIX documentation for deployment modes: https://apisix.apache.org/docs/apisix/deployment-modes/"
    exit 1
fi

if ! grep -q 'role_data_plane:' "${PREFIX}/conf/config.yaml"; then
    echo "Error: ${PREFIX}/conf/config.yaml does not contain 'role_data_plane:'."
    echo "Please refer to the APISIX documentation for deployment modes: https://apisix.apache.org/docs/apisix/deployment-modes/"
    exit 1
fi

if ! grep -q 'config_provider: yaml' "${PREFIX}/conf/config.yaml"; then
    echo "Error: ${PREFIX}/conf/config.yaml does not contain 'config_provider: yaml'. Config provider must be set to 'yaml' for standalone mode."
    echo "Please refer to the APISIX documentation for deployment modes: https://apisix.apache.org/docs/apisix/deployment-modes/"
    exit 1
fi
