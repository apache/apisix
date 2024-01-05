---
title: Deployment modes
keywords:
  - API Gateway
  - Apache APISIX
  - APISIX deployment modes
description: Documentation about the three deployment modes of Apache APISIX.
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

APISIX has three different deployment modes for different production use cases. The table below summarises the deployment modes:

| Deployment mode | Roles                      | Description                                                                                               |
|-----------------|----------------------------|-----------------------------------------------------------------------------------------------------------|
| traditional     | traditional                | Data plane and control plane are deployed together. `enable_admin` attribute should be disabled manually. |
| decoupled       | data_plane / control_plane | Data plane and control plane are deployed independently.                                                  |
| standalone      | data_plane                 | Only `data_plane` is deployed and the configurations are loaded from a local YAML file.                     |

Each of these deployment modes are explained in detail below.

## Traditional

In the traditional deployment mode, one instance of APISIX will be both the `data_plane` and the `control_plane`.

An example configuration of the traditional deployment mode is shown below:

```yaml title="conf/config.yaml"
apisix:
    node_listen:
        - port: 9080
deployment:
    role: traditional
    role_traditional:
        config_provider: etcd
    admin:
        admin_listen:
            port: 9180
    etcd:
       host:
           - http://${etcd_IP}:${etcd_Port}
       prefix: /apisix
       timeout: 30
#END
```

The instance of APISIX deployed as the traditional role will:

1. Listen on port `9080` to handle user requests, controlled by `node_listen`.
2. Listen on port `9180` to handle Admin API requests, controlled by `admin_listen`.

## Decoupled

In the decoupled deployment mode the `data_plane` and `control_plane` instances of APISIX are deployed separately, i.e., one instance of APISIX is configured to be a *data plane* and the other to be a *control plane*.

The instance of APISIX deployed as the data plane will:

Once the service is started, it will handle the user requests.

The example below shows the configuration of an APISIX instance as *data plane* in the decoupled mode:

```yaml title="conf/config.yaml"
deployment:
    role: data_plane
    role_data_plane:
       config_provider: etcd
#END
```

The instance of APISIX deployed as the control plane will:

1. Listen on port `9180` and handle Admin API requests.

The example below shows the configuration of an APISIX instance as *control plane* in the decoupled mode:

```yaml title="conf/config.yaml"
deployment:
    role: control_plane
    role_control_plane:
        config_provider: etcd
    etcd:
       host:
           - https://${etcd_IP}:${etcd_Port}
       prefix: /apisix
       timeout: 30
#END
```

## Standalone

Turning on the APISIX node in Standalone mode will no longer use the default etcd as the configuration center.

This method is more suitable for two types of users:

1. Kubernetes(k8s)：Declarative API that dynamically updates the routing rules with a full yaml configuration.
2. Different configuration centers: There are many implementations of the configuration center, such as Consul, etc., using the full yaml file for intermediate conversion.

The routing rules in the `conf/apisix.yaml` file are loaded into memory immediately after the APISIX node service starts. And every time interval (default 1 second), will try to detect whether the file content is updated, if there is an update, reload the rule.

*Note*: Reloading and updating routing rules are all hot memory updates. There is no replacement of working processes, since it's a hot update.

Since the current Admin API is based on the etcd configuration center solution, enable Admin API is not allowed when the Standalone mode is enabled.

Standalone mode can only be enabled when we set the role of APISIX as data plane. We set `deployment.role` to `data_plane` and `deployment.role_data_plane.config_provider` to `yaml`.

Refer to the example below:

```yaml
deployment:
  role: data_plane
  role_data_plane:
    config_provider: yaml
#END
```

### How to configure rules

All of the rules are stored in one file which named `conf/apisix.yaml`,
APISIX checks if this file has any change **every second**.
If the file is changed & it ends with `#END`,
APISIX loads the rules from this file and updates its memory.

Here is a mini example:

```yaml
routes:
  -
    uri: /hello
    upstream:
        nodes:
            "127.0.0.1:1980": 1
        type: roundrobin
#END
```

*WARNING*: APISIX will not load the rules into memory from file `conf/apisix.yaml` if there is no `#END` at the end.

Environment variables can also be used like so:

```yaml
routes:
  -
    uri: /hello
    upstream:
        nodes:
            "${{UPSTREAM_ADDR}}": 1
        type: roundrobin
#END
```

*WARNING*: When using docker to deploy in standalone mode. New environment variables added in `apisix.yaml` while APISIX is running will only take effect after a reload.

### How to configure Route

Single Route：

```yaml
routes:
  -
    uri: /hello
    upstream:
        nodes:
            "127.0.0.1:1980": 1
        type: roundrobin
#END
```

Multiple Routes：

```yaml
routes:
  -
    uri: /hello
    upstream:
        nodes:
            "127.0.0.1:1980": 1
        type: roundrobin
  -
    uri: /hello2
    upstream:
        nodes:
            "127.0.0.1:1981": 1
        type: roundrobin
#END
```

### How to configure Route + Service

```yml
routes:
    -
        uri: /hello
        service_id: 1
services:
    -
        id: 1
        upstream:
            nodes:
                "127.0.0.1:1980": 1
            type: roundrobin
#END
```

### How to configure Route + Upstream

```yml
routes:
    -
        uri: /hello
        upstream_id: 1
upstreams:
    -
        id: 1
        nodes:
            "127.0.0.1:1980": 1
        type: roundrobin
#END
```

### How to configure Route + Service + Upstream

```yml
routes:
    -
        uri: /hello
        service_id: 1
services:
    -
        id: 1
        upstream_id: 2
upstreams:
    -
        id: 2
        nodes:
            "127.0.0.1:1980": 1
        type: roundrobin
#END
```

### How to configure Plugins

```yml
# plugins listed here will be hot reloaded and override the boot configuration
plugins:
  - name: ip-restriction
  - name: jwt-auth
  - name: mqtt-proxy
    stream: true # set 'stream' to true for stream plugins
#END
```

### How to enable SSL

```yml
ssls:
    -
        cert: |
            -----BEGIN CERTIFICATE-----
            MIIDrzCCApegAwIBAgIJAI3Meu/gJVTLMA0GCSqGSIb3DQEBCwUAMG4xCzAJBgNV
            BAYTAkNOMREwDwYDVQQIDAhaaGVqaWFuZzERMA8GA1UEBwwISGFuZ3pob3UxDTAL
            BgNVBAoMBHRlc3QxDTALBgNVBAsMBHRlc3QxGzAZBgNVBAMMEmV0Y2QuY2x1c3Rl
            ci5sb2NhbDAeFw0yMDEwMjgwMzMzMDJaFw0yMTEwMjgwMzMzMDJaMG4xCzAJBgNV
            BAYTAkNOMREwDwYDVQQIDAhaaGVqaWFuZzERMA8GA1UEBwwISGFuZ3pob3UxDTAL
            BgNVBAoMBHRlc3QxDTALBgNVBAsMBHRlc3QxGzAZBgNVBAMMEmV0Y2QuY2x1c3Rl
            ci5sb2NhbDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAJ/qwxCR7g5S
            s9+VleopkLi5pAszEkHYOBpwF/hDeRdxU0I0e1zZTdTlwwPy2vf8m3kwoq6fmNCt
            tdUUXh5Wvgi/2OA8HBBzaQFQL1Av9qWwyES5cx6p0ZBwIrcXQIsl1XfNSUpQNTSS
            D44TGduXUIdeshukPvMvLWLezynf2/WlgVh/haWtDG99r/Gj3uBdjl0m/xGvKvIv
            NFy6EdgG9fkwcIalutjrUnGl9moGjwKYu4eXW2Zt5el0d1AHXUsqK4voe0p+U2Nz
            quDmvxteXWdlsz8o5kQT6a4DUtWhpPIfNj9oZfPRs3LhBFQ74N70kVxMOCdec1lU
            bnFzLIMGlz0CAwEAAaNQME4wHQYDVR0OBBYEFFHeljijrr+SPxlH5fjHRPcC7bv2
            MB8GA1UdIwQYMBaAFFHeljijrr+SPxlH5fjHRPcC7bv2MAwGA1UdEwQFMAMBAf8w
            DQYJKoZIhvcNAQELBQADggEBAG6NNTK7sl9nJxeewVuogCdMtkcdnx9onGtCOeiQ
            qvh5Xwn9akZtoLMVEdceU0ihO4wILlcom3OqHs9WOd6VbgW5a19Thh2toxKidHz5
            rAaBMyZsQbFb6+vFshZwoCtOLZI/eIZfUUMFqMXlEPrKru1nSddNdai2+zi5rEnM
            HCot43+3XYuqkvWlOjoi9cP+C4epFYrxpykVbcrtbd7TK+wZNiK3xtDPnVzjdNWL
            geAEl9xrrk0ss4nO/EreTQgS46gVU+tLC+b23m2dU7dcKZ7RDoiA9bdVc4a2IsaS
            2MvLL4NZ2nUh8hAEHiLtGMAV3C6xNbEyM07hEpDW6vk6tqk=
            -----END CERTIFICATE-----
        key: |
            -----BEGIN PRIVATE KEY-----
            MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQCf6sMQke4OUrPf
            lZXqKZC4uaQLMxJB2DgacBf4Q3kXcVNCNHtc2U3U5cMD8tr3/Jt5MKKun5jQrbXV
            FF4eVr4Iv9jgPBwQc2kBUC9QL/alsMhEuXMeqdGQcCK3F0CLJdV3zUlKUDU0kg+O
            Exnbl1CHXrIbpD7zLy1i3s8p39v1pYFYf4WlrQxvfa/xo97gXY5dJv8RryryLzRc
            uhHYBvX5MHCGpbrY61JxpfZqBo8CmLuHl1tmbeXpdHdQB11LKiuL6HtKflNjc6rg
            5r8bXl1nZbM/KOZEE+muA1LVoaTyHzY/aGXz0bNy4QRUO+De9JFcTDgnXnNZVG5x
            cyyDBpc9AgMBAAECggEAatcEtehZPJaCeClPPF/Cwbe9YoIfe4BCk186lHI3z7K1
            5nB7zt+bwVY0AUpagv3wvXoB5lrYVOsJpa9y5iAb3GqYMc/XDCKfD/KLea5hwfcn
            BctEn0LjsPVKLDrLs2t2gBDWG2EU+udunwQh7XTdp2Nb6V3FdOGbGAg2LgrSwP1g
            0r4z14F70oWGYyTQ5N8UGuyryVrzQH525OYl38Yt7R6zJ/44FVi/2TvdfHM5ss39
            SXWi00Q30fzaBEf4AdHVwVCRKctwSbrIOyM53kiScFDmBGRblCWOxXbiFV+d3bjX
            gf2zxs7QYZrFOzOO7kLtHGua4itEB02497v+1oKDwQKBgQDOBvCVGRe2WpItOLnj
            SF8iz7Sm+jJGQz0D9FhWyGPvrN7IXGrsXavA1kKRz22dsU8xdKk0yciOB13Wb5y6
            yLsr/fPBjAhPb4h543VHFjpAQcxpsH51DE0b2oYOWMmz+rXGB5Jy8EkP7Q4njIsc
            2wLod1dps8OT8zFx1jX3Us6iUQKBgQDGtKkfsvWi3HkwjFTR+/Y0oMz7bSruE5Z8
            g0VOHPkSr4XiYgLpQxjbNjq8fwsa/jTt1B57+By4xLpZYD0BTFuf5po+igSZhH8s
            QS5XnUnbM7d6Xr/da7ZkhSmUbEaMeHONSIVpYNgtRo4bB9Mh0l1HWdoevw/w5Ryt
            L/OQiPhfLQKBgQCh1iG1fPh7bbnVe/HI71iL58xoPbCwMLEFIjMiOFcINirqCG6V
            LR91Ytj34JCihl1G4/TmWnsH1hGIGDRtJLCiZeHL70u32kzCMkI1jOhFAWqoutMa
            7obDkmwraONIVW/kFp6bWtSJhhTQTD4adI9cPCKWDXdcCHSWj0Xk+U8HgQKBgBng
            t1HYhaLzIZlP/U/nh3XtJyTrX7bnuCZ5FhKJNWrYjxAfgY+NXHRYCKg5x2F5j70V
            be7pLhxmCnrPTMKZhik56AaTBOxVVBaYWoewhUjV4GRAaK5Wc8d9jB+3RizPFwVk
            V3OU2DJ1SNZ+W2HBOsKrEfwFF/dgby6i2w6MuAP1AoGBAIxvxUygeT/6P0fHN22P
            zAHFI4v2925wYdb7H//D8DIADyBwv18N6YH8uH7L+USZN7e4p2k8MGGyvTXeC6aX
            IeVtU6fH57Ddn59VPbF20m8RCSkmBvSdcbyBmqlZSBE+fKwCliKl6u/GH0BNAWKz
            r8yiEiskqRmy7P7MY9hDmEbG
            -----END PRIVATE KEY-----
        snis:
            - "yourdomain.com"
#END
```

### How to configure global rule

```yaml
global_rules:
    -
        id: 1
        plugins:
            response-rewrite:
                body: "hello\n"
#END
```

### How to configure consumer

```yaml
consumers:
  - username: jwt
    plugins:
        jwt-auth:
            key: user-key
            secret: my-secret-key
#END
```

### How to configure plugin metadata

```yaml
upstreams:
  - id: 1
    nodes:
      "127.0.0.1:1980": 1
    type: roundrobin
routes:
  -
    uri: /hello
    upstream_id: 1
    plugins:
        http-logger:
            batch_max_size: 1
            uri: http://127.0.0.1:1980/log
plugin_metadata:
  - id: http-logger # note the id is the plugin name
    log_format:
        host: "$host",
        remote_addr: "$remote_addr"
#END
```

### How to configure stream route

```yaml
stream_routes:
  - server_addr: 127.0.0.1
    server_port: 1985
    id: 1
    upstream_id: 1
    plugins:
      mqtt-proxy:
        protocol_name: "MQTT"
        protocol_level: 4
upstreams:
  - nodes:
      "127.0.0.1:1995": 1
    type: roundrobin
    id: 1
#END
```

### How to configure protos

```yaml
protos:
  - id: helloworld
    desc: hello world
    content: >
      syntax = "proto3";
      package helloworld;

      service Greeter {
        rpc SayHello (HelloRequest) returns (HelloReply) {}
      }
      message HelloRequest {
        string name = 1;
      }
      message HelloReply {
        string message = 1;
      }
#END
```
