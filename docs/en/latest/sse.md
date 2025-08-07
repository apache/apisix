---
title: sse
---

# Summary

The `sse` plugin enables support for **Server-Sent Events (SSE)** by configuring APISIX to correctly proxy long-lived HTTP connections used in streaming scenarios.

SSE allows servers to push updates to clients over a single HTTP connection using the `text/event-stream` content type. This plugin ensures buffering is disabled, proper timeouts are set, and necessary response headers are applied.

# Attributes

| Name                    | Type    | Default      | Required | Description                                                                                                                                       |
| ----------------------- | ------- | ------------ | -------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| `proxy_read_timeout`    | Integer | `3600`       | False    | Timeout in seconds for reading a response from the upstream server. A value of `0` disables the timeout. This should be long for SSE connections. |
| `override_content_type` | Boolean | `true`       | False    | Whether to force the `Content-Type` header to `text/event-stream; charset=utf-8`.                                                                 |
| `connection_header`     | String  | `keep-alive` | False    | Sets the `Connection` response header.                                                                                                            |
| `cache_control`         | String  | `no-cache`   | False    | Sets the `Cache-Control` response header.                                                                                                         |

# How It Works

When enabled, the plugin makes the following adjustments:

- Disables response and request buffering using NGINX variables.
- Sets a long read timeout (`proxy_read_timeout`) to support streaming.
- Optionally overrides the `Content-Type` to `text/event-stream; charset=utf-8`.
- Sets headers necessary for SSE:
  - `X-Accel-Buffering: no`
  - `Connection`
  - `Cache-Control`

These settings are required to ensure that the SSE connection remains open and data can be streamed to the client in real time.

# Example Configuration

```json
{
  "name": "sse",
  "priority": 1005,
  "config": {
    "proxy_read_timeout": 7200,
    "override_content_type": true,
    "connection_header": "keep-alive",
    "cache_control": "no-cache"
  }
}
```


# Enabling the Plugin on a Route

```
curl http://127.0.0.1:9180/apisix/admin/routes/1 -X PUT -d '
{
  "uri": "/sse",
  "plugins": {
    "sse": {
      "proxy_read_timeout": 7200,
      "override_content_type": true,
      "connection_header": "keep-alive",
      "cache_control": "no-cache"
    }
  },
  "upstream": {
    "type": "roundrobin",
    "nodes": {
      "httpbin.org:80": 1
    }
  }
}'
```

This example enables the plugin on the /sse route and sets a 2-hour timeout for SSE connections, ensuring the correct headers and proxy behavior are applied.


# Notes

This plugin is only relevant for routes that serve SSE (e.g., real-time feeds, logs, event notifications).

SSE is a one-way communication protocol (server → client). This plugin does not support bidirectional protocols like WebSocket.

If your upstream already sets the correct Content-Type, you can disable the override using "override_content_type": false.

Ensure your upstream service flushes events frequently to keep the SSE connection alive.

# Disabling the Plugin

To disable the sse plugin on a route:

```
curl http://127.0.0.1:9180/apisix/admin/routes/1 -X PATCH -d '
{
  "plugins": {
    "sse": null
  }
}'
```

# Changelog

| Version | Description                                     |
| ------- | ----------------------------------------------- |
| 0.1     | Initial version of the plugin with SSE support. |

