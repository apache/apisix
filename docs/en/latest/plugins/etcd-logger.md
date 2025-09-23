
# etcd-logger

## Description

The `etcd-logger` Plugin pushes request and response logs in batches to [etcd](https://etcd.io/). It supports customizable log formats, conditional logging of request/response bodies, and batch processing to efficiently store logs in etcd. This plugin is useful for scenarios where you want to persist API logs in a distributed key-value store for later analysis or integration with other systems.

## Attributes

| Name                  | Type           | Required | Default              | Description                                                                 |
|-----------------------|----------------|----------|----------------------|-----------------------------------------------------------------------------|
| auth                  | object         | True     |                      | etcd authentication configuration. Contains `username` and `password`.      |
| auth.username         | string         | True     |                      | Username for etcd authentication.                                           |
| auth.password         | string         | True     |                      | Password for etcd authentication.                                           |
| etcd                  | object         | True     |                      | etcd connection configuration.                                              |
| etcd.urls             | array[string]  | True     |                      | List of etcd server URLs (e.g., `http://host:port`).                        |
| etcd.key_prefix       | string         | False    | `/apisix/logs`       | Prefix for keys used to store logs in etcd.                                 |
| etcd.ttl              | integer        | False    | 0                    | Time-to-live for log keys in seconds. `0` means no TTL.                     |
| log_format            | object         | False    |                      | Custom log format as key-value pairs (JSON). Supports APISIX/NGINX variables.|
| timeout               | integer        | False    | 10                   | Timeout for etcd requests (seconds).                                        |
| ssl_verify            | boolean        | False    | true                 | Whether to verify SSL certificates.                                         |
| include_req_body      | boolean        | False    | false                | If true, include the request body in the log.                               |
| include_req_body_expr | array[array]   | False    |                      | Conditions (lua-resty-expr) for including request body.                     |
| include_resp_body     | boolean        | False    | false                | If true, include the response body in the log.                              |
| include_resp_body_expr| array[array]   | False    |                      | Conditions (lua-resty-expr) for including response body.                    |
| http_methods          | array[string]  | False    | []                   | HTTP methods to log. Empty array means all methods.                         |

**Note:** `encrypt_fields = {"auth.password"}` is defined in the schema, so the password is stored encrypted in etcd. See [encrypted storage fields](../plugin-develop.md#encrypted-storage-fields).

This plugin uses batch processors to aggregate and process log entries in batches, reducing the frequency of writes to etcd. The batch processor submits data every 5 seconds or when the queue reaches 1000 entries. See [Batch Processor](../batch-processor.md#configuration) for more information.

## Plugin Metadata

| Name       | Type   | Required | Default | Description                                                                 |
|------------|--------|----------|---------|-----------------------------------------------------------------------------|
| log_format | object | False    |         | Custom log format as key-value pairs (JSON). Supports APISIX/NGINX variables.|

## Examples

### Basic Configuration

Enable the `etcd-logger` plugin on a route to log requests and responses to etcd:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
	-H "X-API-KEY: ${admin_key}" \
	-d '{
		"id": "etcd-logger-route",
		"uri": "/anything",
		"plugins": {
			"etcd-logger": {
				"auth": {
					"username": "etcduser",
					"password": "etcdpass"
				},
				"etcd": {
					"urls": ["http://127.0.0.1:2379"],
					"key_prefix": "/apisix/logs",
					"ttl": 3600
				},
				"timeout": 10,
				"ssl_verify": true
			}
		},
		"upstream": {
			"nodes": {"httpbin.org:80": 1},
			"type": "roundrobin"
		}
	}'
```

### Custom Log Format

You can customize the log format using the `log_format` attribute or plugin metadata. For example, to log only the client IP and request URI:

```shell
curl "http://127.0.0.1:9180/apisix/admin/plugin_metadata/etcd-logger" -X PUT \
	-H "X-API-KEY: ${admin_key}" \
	-d '{
		"log_format": {
			"client_ip": "$remote_addr",
			"uri": "$request_uri"
		}
	}'
```

### Conditional Logging of Request/Response Bodies

To log the request body only for POST requests:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
	-H "X-API-KEY: ${admin_key}" \
	-d '{
		"id": "etcd-logger-route",
		"uri": "/anything",
		"plugins": {
			"etcd-logger": {
				...,
				"include_req_body": true,
				"http_methods": ["POST"]
			}
		},
		"upstream": {
			"nodes": {"httpbin.org:80": 1},
			"type": "roundrobin"
		}
	}'
```

## Notes

- If you set a custom `log_format`, only the specified fields will be logged.
- If you enable `include_req_body` or `include_resp_body`, the plugin will attempt to log the respective bodies, subject to NGINX memory limitations.
- The plugin supports conditional logging of bodies using `include_req_body_expr` and `include_resp_body_expr` (see [lua-resty-expr](https://github.com/api7/lua-resty-expr)).
- The `http_methods` attribute allows you to restrict logging to specific HTTP methods.

## See Also

- [Batch Processor](../batch-processor.md)
- [Plugin Metadata](../terminology/plugin-metadata.md)
- [APISIX Variables](../apisix-variable.md)
- [NGINX Variables](http://nginx.org/en/docs/varindex.html)
