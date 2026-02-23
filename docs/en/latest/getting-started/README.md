---
title: Get APISIX
description: This tutorial uses a script to quickly install Apache APISIX in your local environment and verify it through the Admin API.
---

<head>
  <link rel="canonical" href="https://docs.api7.ai/apisix/getting-started/" />
</head>

> The Getting Started tutorials are contributed by [API7.ai](https://api7.ai/).

Developed and donated by API7.ai, Apache APISIX is an open source, dynamic, scalable, and high-performance cloud native API gateway for all your APIs and microservices. It is a [top-level project](https://projects.apache.org/project.html?apisix) of the Apache Software Foundation.

You can use APISIX API Gateway as a traffic entrance to process all business data. It offers features including dynamic routing, dynamic upstream, dynamic certificates, A/B testing, canary release, blue-green deployment, limit rate, defense against malicious attacks, metrics, monitoring alarms, service observability, service governance, and more.

This tutorial uses a script to quickly install [Apache APISIX](https://api7.ai/apisix) in your local environment and verifies the installation through the Admin API.

## Prerequisite(s)

The quickstart script relies on several components:

* [Docker](https://docs.docker.com/get-docker/) is used to install the containerized **etcd** and **APISIX**.
* [curl](https://curl.se/) is used to send requests to APISIX for validation.

## Get APISIX

:::caution

To provide a better experience in this tutorial, the authorization of Admin API is switched off by default. Please turn on the authorization of Admin API in the production environment.

:::
APISIX can be easily installed and started with the quickstart script:

```shell
curl -sL https://run.api7.ai/apisix/quickstart | sh
```

The script should start two Docker containers, _apisix-quickstart_ and _etcd_. APISIX uses etcd to save and synchronize configurations. Both the etcd and the APISIX use [**host**](https://docs.docker.com/network/host/) Docker network mode. That is, the APISIX can be accessed from local.

You will see the following message once APISIX is ready:

```text
✔ APISIX is ready!
```

## Validate

Once APISIX is running, you can use curl to interact with it. Send a simple HTTP request to validate if APISIX is working properly:

```shell
curl "http://127.0.0.1:9080" --head | grep Server
```

If everything is ok, you will get the following response:

```text
Server: APISIX/Version
```

`Version` refers to the version of APISIX that you have installed. For example, `APISIX/3.3.0`.

You now have APISIX installed and running successfully!​

APISIX includes a built-in Dashboard UI, accessible at http://127.0.0.1:9180/ui. For more guidance, please read [Apache APISIX Dashboard](../dashboard.md).

## Next Steps

The following tutorial is based on the working APISIX, please keep everything running and move on to the next step.

* [Configure Routes](configure-routes.md)
* [Load Balancing](load-balancing.md)
* [Rate Limiting](rate-limiting.md)
* [Key Authentication](key-authentication.md)
