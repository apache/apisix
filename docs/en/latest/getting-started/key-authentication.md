---
title: Key Authentication
slug: /getting-started/key-authentication
---

<head>
  <link rel="canonical" href="https://docs.api7.ai/apisix/getting-started/key-authentication" />
</head>

> The Getting Started tutorials are contributed by [API7.ai](https://api7.ai/).

An API gateway's primary role is to connect API consumers and providers. For security reasons, it should authenticate and authorize consumers before access to internal resources.

![Key Authentication](https://static.apiseven.com/uploads/2023/02/08/8mRaK3v1_consumer.png)

APISIX has a flexible plugin extension system and a number of existing plugins for user authentication and authorization. For example:

- [Key Authentication](https://apisix.apache.org/docs/apisix/plugins/key-auth/)
- [Basic Authentication](https://apisix.apache.org/docs/apisix/plugins/basic-auth/)
- [JSON Web Token (JWT) Authentication](https://apisix.apache.org/docs/apisix/plugins/jwt-auth/)
- [Keycloak](https://apisix.apache.org/docs/apisix/plugins/authz-keycloak/)
- [Casdoor](https://apisix.apache.org/docs/apisix/plugins/authz-casdoor/)
- [Wolf RBAC](https://apisix.apache.org/docs/apisix/plugins/wolf-rbac/)
- [OpenID Connect](https://apisix.apache.org/docs/apisix/plugins/openid-connect/)
- [Central Authentication Service (CAS)](https://apisix.apache.org/docs/apisix/plugins/cas-auth/)
- [HMAC](https://apisix.apache.org/docs/apisix/plugins/hmac-auth/)
- [Casbin](https://apisix.apache.org/docs/apisix/plugins/authz-casbin/)
- [LDAP](https://apisix.apache.org/docs/apisix/plugins/ldap-auth/)
- [Open Policy Agent (OPA)](https://apisix.apache.org/docs/apisix/plugins/opa/)
- [Forward Authentication](https://apisix.apache.org/docs/apisix/plugins/forward-auth/)
- [Multiple Authentications](https://apisix.apache.org/docs/apisix/plugins/multi-auth/)

In this tutorial, you will create a _consumer_ with _key authentication_, and learn how to enable and disable key authentication.

## What is a Consumer

A Consumer is an application or a developer who consumes the API.

In APISIX, a Consumer requires a unique _username_ and an authentication _plugin_ from the list above to be created.

## What is Key Authentication

Key authentication is a relatively simple but widely used authentication approach. The idea is as follows:

1. Administrator adds an authentication key (API key) to the Route.
2. API consumers add the key to the query string or headers for authentication when sending requests.

## Enable Key Authentication

### Prerequisite(s)

1. Complete [Get APISIX](./README.md) to install APISIX.
2. Complete [Configure Routes](./configure-routes.md#what-is-a-route).

### Create a Consumer

Let's create a consumer named `tom` and enable the `key-auth` plugin with an API key `secret-key`. All requests sent with the key `secret-key` should be authenticated as `tom`.

:::caution

Please use a complex key in the Production environment.

:::

```shell
curl -i "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT -d '
{
  "username": "tom",
  "plugins": {
    "key-auth": {
      "key": "secret-key"
    }
  }
}'
```

You will receive an `HTTP/1.1 201 Created` response if the consumer was created successfully.

### Enable Authentication

Inheriting the route `getting-started-ip` from [Configure Routes](./configure-routes.md), we only need to use the `PATCH` method to add the `key-auth` plugin to the route:

```shell
curl -i "http://127.0.0.1:9180/apisix/admin/routes/getting-started-ip" -X PATCH -d '
{
  "plugins": {
    "key-auth": {}
  }
}'
```

You will receive an `HTTP/1.1 201 Created` response if the plugin was added successfully.

### Validate

Let's validate the authentication in the following scenarios:

#### 1. Send a request without any key

Send a request without the `apikey` header.

```shell
curl -i "http://127.0.0.1:9080/ip"
```

Since you enabled the key authentication, you will receive an unauthorized response with `HTTP/1.1 401 Unauthorized`.

```text
HTTP/1.1 401 Unauthorized
Date: Wed, 08 Feb 2023 09:38:36 GMT
Content-Type: text/plain; charset=utf-8
Transfer-Encoding: chunked
Connection: keep-alive
Server: APISIX/3.1.0
```

#### 2. Send a request with a wrong key

Send a request with a wrong key (e.g. `wrong-key`) in the `apikey` header.

```shell
curl -i "http://127.0.0.1:9080/ip" -H 'apikey: wrong-key'
```

Since the key is incorrect, you will receive an unauthorized response with `HTTP/1.1 401 Unauthorized`.

```text
HTTP/1.1 401 Unauthorized
Date: Wed, 08 Feb 2023 09:38:27 GMT
Content-Type: text/plain; charset=utf-8
Transfer-Encoding: chunked
Connection: keep-alive
Server: APISIX/3.1.0
```

#### 3. Send a request with the correct key

Send a request with the correct key (`secret-key`) in the `apikey` header.

```shell
curl -i "http://127.0.0.1:9080/ip" -H 'apikey: secret-key'
```

You will receive an `HTTP/1.1 200 OK` response.

```text
HTTP/1.1 200 OK
Content-Type: application/json
Content-Length: 44
Connection: keep-alive
Date: Thu, 09 Feb 2023 03:27:57 GMT
Access-Control-Allow-Origin: *
Access-Control-Allow-Credentials: true
Server: APISIX/3.1.0
```

### Disable Authentication

Disable the key authentication plugin by setting the `_meta.disable` parameter to `true`.

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/getting-started-ip" -X PATCH -d '
{
  "plugins": {
    "key-auth": {
      "_meta": {
        "disable": true
      }
    }
  }
}'
```

You can send a request without any key to validate:

```shell
curl -i "http://127.0.0.1:9080/ip"
```

Because you have disabled the key authentication plugin, you will receive an `HTTP/1.1 200 OK` response.

## What's Next

You have learned how to configure key authentication for a route. In the next tutorial, you will learn how to configure rate limiting.
