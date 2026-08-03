---
title: Proxy LocalAI APIs with Apache APISIX
keywords:
  - Apache APISIX
  - AI Gateway
  - LocalAI
  - OpenAI-compatible API
description: This tutorial shows how to proxy LocalAI's OpenAI-compatible APIs through Apache APISIX.
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

[LocalAI](https://localai.io/) exposes local models through OpenAI-compatible APIs. In this tutorial, you will place APISIX in front of LocalAI, proxy only model discovery and chat completions, and verify non-streaming and streaming responses with a real model.

The base configuration in this tutorial provides routing, upstream authentication forwarding, streaming, and timeouts. It does not enable APISIX authentication, rate limiting, observability, model routing, or failover unless you configure the corresponding plugins.

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) with Docker Engine 28.0.0 or later
- [curl](https://curl.se/) and [jq](https://jqlang.github.io/jq/)
- Apache APISIX 3.17.0 or later. The [`proxy-buffering`](../plugins/proxy-buffering.md) Plugin used for streaming was added in APISIX 3.17.0.

This tutorial assumes that APISIX can reach LocalAI at `127.0.0.1:8080`. This address works when both processes run on the same host or APISIX uses Docker host networking, as in the APISIX [getting started guide](../getting-started/README.md). For other deployments, replace the upstream node with a reachable LocalAI address, such as `localai:8080` on a shared Docker network.

## Start LocalAI with a Model

Set a demonstration LocalAI API key. Use a secret value in production.

```shell
export LOCALAI_API_KEY="localai-demo-key"
```

Start LocalAI 4.7.1 with the CPU-friendly `llama-3.2-1b-instruct:q4_k_m` model from the LocalAI model gallery:

```shell
docker run --detach \
  --name localai \
  --publish 127.0.0.1:8080:8080 \
  --env LOCALAI_API_KEY="${LOCALAI_API_KEY}" \
  --env LOCALAI_BASE_URL="http://127.0.0.1:9080" \
  --volume localai-models:/models \
  --volume localai-backends:/backends \
  localai/localai:v4.7.1 \
  run llama-3.2-1b-instruct:q4_k_m
```

With Docker Engine 28.0.0 or later, binding the published port to `127.0.0.1` limits access to the Docker host. On older Engine releases, upgrade or additionally block port `8080` with the host firewall. See [Docker port publishing](https://docs.docker.com/engine/network/port-publishing/) for details.

The first start downloads the model and its backend and can take several minutes. Check LocalAI until it is ready:

```shell
curl --fail --retry 120 --retry-delay 5 --retry-max-time 900 \
  --retry-connrefused "http://127.0.0.1:8080/readyz" \
  -H "Authorization: Bearer ${LOCALAI_API_KEY}"
```

The legacy `LOCALAI_API_KEY` grants full LocalAI administrator access. Use [LocalAI user authentication](https://localai.io/docs/features/authentication/) when you need users, roles, or per-user API keys.

## Create a Route

Set `admin_key` to the key configured in `deployment.admin.admin_key` for your APISIX installation:

```shell
export admin_key="<your-admin-api-key>"
```

The local APISIX quickstart disables Admin API authorization for testing. If you use it, omit the `X-API-KEY` headers below. Keep Admin API authorization enabled outside a local test environment.

Create a Route for LocalAI's OpenAI-compatible APIs:

```shell
curl --fail-with-body "http://127.0.0.1:9180/apisix/admin/routes/localai" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -H "Content-Type: application/json" \
  -d '{
    "uris": [
      "/v1/models",
      "/v1/chat/completions"
    ],
    "plugins": {
      "proxy-buffering": {
        "disable_proxy_buffering": true
      },
      "proxy-rewrite": {
        "headers": {
          "set": {
            "X-Forwarded-Host": "$host",
            "X-Forwarded-Proto": "$scheme"
          }
        }
      }
    },
    "timeout": {
      "connect": 60,
      "send": 3600,
      "read": 3600
    },
    "upstream": {
      "type": "roundrobin",
      "scheme": "http",
      "pass_host": "pass",
      "nodes": {
        "127.0.0.1:8080": 1
      }
    }
  }'
```

The Route forwards the LocalAI `Authorization` header without changing it. The `proxy-buffering` Plugin lets clients receive streaming Server-Sent Events (SSE) without response buffering. The send and read timeouts apply to individual upstream I/O operations, not to the total request duration.

Using exact paths prevents this Route from exposing LocalAI's Web UI and management endpoints, including management endpoints under `/v1/backend/*`. Add separate, explicit paths only when clients require other LocalAI APIs.

## Verify the Route

List the available models through APISIX:

```shell
curl --fail-with-body "http://127.0.0.1:9080/v1/models" \
  -H "Authorization: Bearer ${LOCALAI_API_KEY}" | \
  jq -e '.data[] | select(.id == "llama-3.2-1b-instruct:q4_k_m")'
```

Send a non-streaming chat completion request:

```shell
curl --fail-with-body "http://127.0.0.1:9080/v1/chat/completions" \
  -H "Authorization: Bearer ${LOCALAI_API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llama-3.2-1b-instruct:q4_k_m",
    "messages": [
      {"role": "user", "content": "Reply with exactly: APISIX reaches LocalAI"}
    ],
    "temperature": 0,
    "max_tokens": 32
  }' | \
  jq -e '
    .object == "chat.completion" and
    (.choices[0].message.content | type == "string" and length > 0)
  '
```

Send a streaming chat completion request:

```shell
stream_output=$(mktemp)

(
  set -o pipefail

  curl --fail-with-body --no-buffer "http://127.0.0.1:9080/v1/chat/completions" \
    -H "Authorization: Bearer ${LOCALAI_API_KEY}" \
    -H "Content-Type: application/json" \
    -d '{
      "model": "llama-3.2-1b-instruct:q4_k_m",
      "messages": [
        {"role": "user", "content": "Count from one to five."}
      ],
      "stream": true,
      "temperature": 0,
      "max_tokens": 32
    }' | tee "${stream_output}"
) &&
  test "$(grep -c '^data:' "${stream_output}")" -gt 1 &&
  grep -q '^data: \[DONE\]$' "${stream_output}"

stream_status=$?
rm -f "${stream_output}"
test "${stream_status}" -eq 0
```

You should receive multiple `data:` events followed by `data: [DONE]`.

Confirm that a LocalAI management endpoint is not exposed by the Route:

```shell
test "$(curl --silent --output /dev/null --write-out "%{http_code}" \
  "http://127.0.0.1:9080/v1/backend/monitor" \
  -H "Authorization: Bearer ${LOCALAI_API_KEY}")" = "404"
```

APISIX should return `404`.

## Add APISIX Client Authentication

LocalAI authentication protects the upstream. To authenticate clients at the gateway as a separate layer, create an APISIX Consumer and `key-auth` Credential:

```shell
curl --fail-with-body "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -H "Content-Type: application/json" \
  -d '{"username": "localai-client"}'

curl --fail-with-body "http://127.0.0.1:9180/apisix/admin/consumers/localai-client/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -H "Content-Type: application/json" \
  -d '{
    "id": "localai-client-key",
    "plugins": {
      "key-auth": {
        "key": "gateway-client-key"
      }
    }
  }'
```

The key values in this tutorial are for local testing. Use separate, secret values in production.

Enable `key-auth` on the Route. The APISIX key uses the `apikey` header, while the LocalAI key remains in the `Authorization` header.

```shell
curl --fail-with-body "http://127.0.0.1:9180/apisix/admin/routes/localai" -X PATCH \
  -H "X-API-KEY: ${admin_key}" \
  -H "Content-Type: application/json" \
  -d '{
    "plugins": {
      "key-auth": {
        "header": "apikey",
        "hide_credentials": true
      }
    }
  }'
```

The requests below carry the APISIX key only in the `apikey` header. Header lookup takes precedence over query lookup. If both forms are present, `hide_credentials` removes only the authenticated header, and the duplicate `apikey` query value is still forwarded upstream. Never put the gateway key in the query string or send both forms.

Send both independent credentials to access LocalAI through APISIX:

```shell
curl --fail-with-body "http://127.0.0.1:9080/v1/models" \
  -H "apikey: gateway-client-key" \
  -H "Authorization: Bearer ${LOCALAI_API_KEY}" | \
  jq -e '.data[] | select(.id == "llama-3.2-1b-instruct:q4_k_m")'
```

A request without an APISIX gateway credential is rejected by APISIX. A request with the APISIX key but without the LocalAI bearer token is rejected by LocalAI.

Verify both rejection cases. Each command should return `401`:

```shell
test "$(curl --silent --output /dev/null --write-out "%{http_code}" \
  "http://127.0.0.1:9080/v1/models" \
  -H "Authorization: Bearer ${LOCALAI_API_KEY}")" = "401" &&
  test "$(curl --silent --output /dev/null --write-out "%{http_code}" \
    "http://127.0.0.1:9080/v1/models" \
    -H "apikey: gateway-client-key")" = "401"
```

## Production Considerations

- This tutorial configures a local HTTP Route. Configure [TLS](../certificate.md) before exposing the Route and set `LOCALAI_BASE_URL` to its public HTTPS URL.
- Do not publish LocalAI on a public interface. Bind it to loopback when APISIX uses host networking, or place APISIX and LocalAI on a private Docker network without publishing LocalAI port `8080`.
- Keep the APISIX Admin API private and rotate its key. Never expose port `9180` publicly.
- Add APISIX authentication, rate limiting, and observability plugins according to your requirements. These capabilities are not enabled by the base Route.
- Add only the exact LocalAI paths your clients require. Do not replace the path list with a broad wildcard.

## Clean Up

Delete the APISIX Route:

```shell
curl --fail-with-body "http://127.0.0.1:9180/apisix/admin/routes/localai" -X DELETE \
  -H "X-API-KEY: ${admin_key}"
```

If you added APISIX client authentication, delete the Consumer and its Credential:

```shell
curl --fail-with-body "http://127.0.0.1:9180/apisix/admin/consumers/localai-client" -X DELETE \
  -H "X-API-KEY: ${admin_key}"
```

Remove the LocalAI container and named volumes:

```shell
docker rm --force localai &&
  docker volume rm localai-models localai-backends &&
  unset LOCALAI_API_KEY admin_key
```

To keep the downloaded model and backend for reuse, omit the `docker volume rm` command.
