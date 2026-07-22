--
-- Licensed to the Apache Software Foundation (ASF) under one or more
-- contributor license agreements.  See the NOTICE file distributed with
-- this work for additional information regarding copyright ownership.
-- The ASF licenses this file to You under the Apache License, Version 2.0
-- (the "License"); you may not use this file except in compliance with
-- the License.  You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--

--- Kubernetes Secret Manager.
--  Fetches secrets from the Kubernetes API server using the pod's ServiceAccount
--  token. This allows APISIX to read Kubernetes Secrets directly from the cluster
--  it is running in, without requiring an external secrets management service.
--
--  URI format:
--    $secret://kubernetes/{manager-id}/{namespace}/{secret-name}/{data-key}
--
--  Example:
--    $secret://kubernetes/my-k8s/default/my-secret/password
--
--  The manager is configured once via the Admin API:
--    PUT /apisix/admin/secrets/kubernetes/my-k8s
--    {
--      "service_account_file": "/var/run/secrets/kubernetes.io/serviceaccount/token",
--      "kubernetes_host": "kubernetes.default.svc",
--      "kubernetes_port": "443",
--      "ssl_verify": true
--    }
--
--  All fields have sensible defaults for in-cluster usage, so the minimal
--  valid configuration is an empty object `{}`.
--
--  TLS note: when ssl_verify is true (the default), the TLS handshake is
--  validated against the nginx-level lua_ssl_trusted_certificate bundle.
--  For in-cluster usage, set apisix.ssl.ssl_trusted_certificate in config.yaml
--  to /var/run/secrets/kubernetes.io/serviceaccount/ca.crt so that the
--  kube-apiserver certificate (signed by the cluster CA) is trusted.

local core = require("apisix.core")
local http = require("resty.http")
local env  = core.env

local io_open = io.open
local find    = core.string.find
local sub     = core.string.sub
local ngx_decode_base64 = ngx.decode_base64

local DEFAULT_SA_FILE = "/var/run/secrets/kubernetes.io/serviceaccount/token"

local schema = {
    type = "object",
    properties = {
        service_account_file = {
            type = "string",
            description = "Path to the ServiceAccount token file. "
                       .. "Defaults to the standard in-cluster path.",
            default = DEFAULT_SA_FILE,
        },
        kubernetes_host = {
            type = "string",
            description = "Kubernetes API server hostname or IP. "
                       .. "Defaults to the KUBERNETES_SERVICE_HOST environment variable.",
        },
        kubernetes_port = {
            type = "string",
            description = "Kubernetes API server port. "
                       .. "Defaults to the KUBERNETES_SERVICE_PORT environment variable.",
        },
        endpoint = {
            type = "string",
            description = "Full base URL of the Kubernetes API server "
                       .. "(e.g. https://kubernetes.default.svc:443). "
                       .. "When set, kubernetes_host and kubernetes_port are ignored. "
                       .. "Useful for testing with plain HTTP mock servers.",
        },
        ssl_verify = {
            type = "boolean",
            description = "Verify the Kubernetes API server TLS certificate. "
                       .. "When true, validation uses the nginx-level "
                       .. "lua_ssl_trusted_certificate bundle; set "
                       .. "apisix.ssl.ssl_trusted_certificate to the cluster CA "
                       .. "(/var/run/secrets/kubernetes.io/serviceaccount/ca.crt) "
                       .. "in config.yaml for in-cluster usage.",
            default = true,
        },
    },
    required = {},
}

local _M = {
    schema = schema,
}


local function read_file(path)
    local f, err = io_open(path, "r")
    if not f then
        return nil, "failed to open file " .. path .. ": " .. err
    end
    local content = f:read("*a")
    f:close()
    if not content or content == "" then
        return nil, "file is empty: " .. path
    end
    return content
end


local function make_request_to_k8s(conf, namespace, secret_name)
    local sa_file = conf.service_account_file or DEFAULT_SA_FILE
    local token, err = read_file(sa_file)
    if not token then
        return nil, err
    end
    -- strip trailing newline
    token = token:gsub("%s+$", "")

    local k8s_host = conf.kubernetes_host
                  or env.fetch_by_uri("$ENV://KUBERNETES_SERVICE_HOST")
                  or os.getenv("KUBERNETES_SERVICE_HOST")

    local k8s_port = conf.kubernetes_port
                  or env.fetch_by_uri("$ENV://KUBERNETES_SERVICE_PORT")
                  or os.getenv("KUBERNETES_SERVICE_PORT")
                  or "443"

    local base_url
    if conf.endpoint then
        base_url = conf.endpoint
    else
        if not k8s_host then
            return nil, "kubernetes_host is not set and KUBERNETES_SERVICE_HOST env var is missing"
        end
        base_url = "https://" .. k8s_host .. ":" .. k8s_port
    end

    local uri = base_url
             .. "/api/v1/namespaces/" .. namespace
             .. "/secrets/" .. secret_name

    core.log.info("fetching Kubernetes secret from: ", uri)

    local httpc = http.new()
    httpc:set_timeout(5000)

    local ssl_verify = conf.ssl_verify
    if ssl_verify == nil then
        ssl_verify = true
    end

    local request_opts = {
        method = "GET",
        headers = {
            ["Authorization"] = "Bearer " .. token,
            ["Accept"] = "application/json",
        },
        ssl_verify = ssl_verify,
    }

    local res, req_err = httpc:request_uri(uri, request_opts)
    if not res then
        return nil, "failed to request Kubernetes API: " .. req_err
    end

    if res.status == 401 or res.status == 403 then
        return nil, "unauthorized to read Kubernetes secret "
               .. namespace .. "/" .. secret_name
               .. " (HTTP " .. res.status .. "): check RBAC permissions for the ServiceAccount"
    end

    if res.status == 404 then
        return nil, "Kubernetes secret not found: " .. namespace .. "/" .. secret_name
    end

    if res.status ~= 200 then
        return nil, "unexpected HTTP status " .. res.status
               .. " from Kubernetes API for secret "
               .. namespace .. "/" .. secret_name
    end

    return res.body
end


-- key format: {namespace}/{secret-name}/{data-key}
local function get(conf, key)
    core.log.info("fetching data from Kubernetes secret for key: ", key)

    local idx1 = find(key, "/")
    if not idx1 then
        return nil, "invalid key format, expected {namespace}/{secret-name}/{data-key}, got: "
               .. key
    end

    local namespace = sub(key, 1, idx1 - 1)
    if namespace == "" then
        return nil, "namespace is empty in key: " .. key
    end

    local rest = sub(key, idx1 + 1)
    local idx2 = find(rest, "/")
    if not idx2 then
        return nil, "invalid key format, missing data-key, expected "
               .. "{namespace}/{secret-name}/{data-key}, got: " .. key
    end

    local secret_name = sub(rest, 1, idx2 - 1)
    if secret_name == "" then
        return nil, "secret-name is empty in key: " .. key
    end

    local data_key = sub(rest, idx2 + 1)
    if data_key == "" then
        return nil, "data-key is empty in key: " .. key
    end

    core.log.info("namespace: ", namespace,
                  ", secret_name: ", secret_name,
                  ", data_key: ", data_key)

    local body, err = make_request_to_k8s(conf, namespace, secret_name)
    if not body then
        return nil, err
    end

    local secret, decode_err = core.json.decode(body)
    if not secret then
        return nil, "failed to decode Kubernetes API response: " .. decode_err
    end

    if not secret.data then
        return nil, "Kubernetes secret " .. namespace .. "/" .. secret_name
               .. " has no data field"
    end

    local encoded_value = secret.data[data_key]
    if not encoded_value then
        return nil, "key '" .. data_key .. "' not found in Kubernetes secret "
               .. namespace .. "/" .. secret_name
    end

    local value = ngx_decode_base64(encoded_value)
    if not value then
        return nil, "failed to base64-decode value for key '" .. data_key
               .. "' in Kubernetes secret " .. namespace .. "/" .. secret_name
    end

    return value
end

_M.get = get


return _M
