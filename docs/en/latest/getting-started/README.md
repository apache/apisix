---
title: Getting Started with Apache APISIX
description: Install and run Apache APISIX in minutes. This guide covers Docker-based setup, verification, basic route configuration, and next steps for production deployment.
---

Apache APISIX is an open-source, high-performance API gateway and AI gateway built for cloud-native architectures. It provides dynamic routing, load balancing, authentication, rate limiting, observability, and 100+ plugins for managing API traffic at scale.

This guide walks you through installing APISIX locally, verifying the installation, and configuring your first API route.

## Prerequisites

Before you begin, ensure you have the following installed:

- [Docker](https://docs.docker.com/get-docker/) (version 20.10 or later) — used to run APISIX and etcd containers
- [curl](https://curl.se/) — used to send requests to APISIX for validation

APISIX uses [etcd](https://etcd.io/) as its configuration store. The quickstart script handles etcd setup automatically.

## Install APISIX

APISIX can be installed with a single command using the quickstart script:

```shell
curl -sL https://run.api7.ai/apisix/quickstart | sh
```

This script starts two Docker containers:

- **apisix-quickstart** — the APISIX gateway, listening on ports 9080 (HTTP) and 9443 (HTTPS)
- **etcd** — the configuration store

Both containers use Docker [host network mode](https://docs.docker.com/network/host/), so APISIX is accessible directly from localhost.

You will see the following message once APISIX is ready:

```text
✔ APISIX is ready!
```

:::caution

The quickstart script disables Admin API authorization by default for ease of use. Always enable Admin API authentication in production environments. See the [Admin API documentation](../admin-api.md) for details.

:::

### Alternative Installation Methods

| Method | Use Case | Documentation |
|--------|----------|---------------|
| Docker Compose | Production-like local setup with custom configuration | [apisix-docker](https://github.com/apache/apisix-docker) |
| Helm Chart | Kubernetes deployment | [apisix-helm-chart](https://github.com/apache/apisix-helm-chart) |
| RPM Package | CentOS/RHEL bare-metal installation | [Installation Guide](../installation-guide.md) |
| Source Build | Development and custom builds | [How to Build](../building-apisix.md) |

## Verify the Installation

Send a request to confirm APISIX is running:

```shell
curl "http://127.0.0.1:9080" --head | grep Server
```

Expected response:

```text
Server: APISIX/3.16.0
```

The version number reflects the APISIX release you installed.

You can also check the Admin API:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" | head -c 200
```

This should return a JSON response confirming the Admin API is accessible.

## Configure Your First Route

A **route** tells APISIX how to match client requests and forward them to upstream services. Create a route that proxies requests to the public httpbin.org service:

```shell
curl -i "http://127.0.0.1:9180/apisix/admin/routes/1" -X PUT -d '
{
  "uri": "/get",
  "upstream": {
    "type": "roundrobin",
    "nodes": {
      "httpbin.org:80": 1
    }
  }
}'
```

Now test the route:

```shell
curl "http://127.0.0.1:9080/get"
```

You should receive a JSON response from httpbin.org, confirming that APISIX is proxying requests correctly.

## Add a Plugin

APISIX provides 100+ built-in [plugins](/plugins/) for authentication, traffic control, observability, and more. Add rate limiting to the route you just created:

```shell
curl -i "http://127.0.0.1:9180/apisix/admin/routes/1" -X PATCH -d '
{
  "plugins": {
    "limit-count": {
      "count": 5,
      "time_window": 60,
      "rejected_code": 429,
      "key_type": "var",
      "key": "remote_addr"
    }
  }
}'
```

This limits each client IP to 5 requests per minute. Send more than 5 requests within 60 seconds to see the rate limit in action:

```shell
for i in $(seq 1 7); do
  echo "Request $i:"
  curl -s -o /dev/null -w "HTTP %{http_code}\n" "http://127.0.0.1:9080/get"
done
```

Requests 1-5 should return `HTTP 200`, while requests 6-7 should return `HTTP 429`.

## Access the Dashboard

APISIX includes a built-in Dashboard UI for visual route and plugin management, accessible at:

```
http://127.0.0.1:9180/ui
```

For more details, see the [Apache APISIX Dashboard documentation](../dashboard.md).

## Clean Up

To stop and remove the quickstart containers:

```shell
docker rm -f apisix-quickstart etcd
```

## Troubleshooting

**APISIX container fails to start**

Check if ports 9080, 9180, or 9443 are already in use:

```shell
lsof -i :9080 -i :9180 -i :9443
```

**etcd connection errors**

Ensure the etcd container is running:

```shell
docker ps | grep etcd
```

If etcd is not running, restart both containers by re-running the quickstart script.

**Admin API returns 401 Unauthorized**

If you have enabled Admin API authentication, include the API key in your requests:

```shell
curl -H "X-API-KEY: your-admin-key" "http://127.0.0.1:9180/apisix/admin/routes"
```

## Next Steps

Now that APISIX is running, explore these tutorials to learn core features:

- [Configure Routes](configure-routes.md) — define routing rules and upstream services
- [Load Balancing](load-balancing.md) — distribute traffic across multiple backend nodes
- [Rate Limiting](rate-limiting.md) — protect services from excessive traffic
- [Key Authentication](key-authentication.md) — secure APIs with API key authentication
- [Plugin Hub](/plugins/) — browse all available plugins
