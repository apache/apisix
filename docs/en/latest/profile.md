---
title: Configuration based on environments
keywords:
  - Apache APISIX
  - API Gateway
  - Configuration
  - Environment
description: This document describes how you can change APISIX configuration based on environments.
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

Extracting configuration from the code makes APISIX adaptable to changes in the operating environments. For example, APISIX can be deployed in a development environment for testing and then moved to a production environment. The configuration for APISIX in these environments would be different.

APISIX supports managing multiple configurations through environment variables in two different ways:

1. Using environment variables in the configuration file
2. Using an environment variable to switch between multiple configuration profiles

## Using environment variables in the configuration file

This is useful when you want to change some configurations based on the environment.

To use environment variables, you can use the syntax `key_name: ${{ENVIRONMENT_VARIABLE_NAME:=}}`. You can also set a default value to fall back to if no environment variables are set by adding it to the configuration as `key_name: ${{ENVIRONMENT_VARIABLE_NAME:=VALUE}}`. The example below shows how you can modify your configuration file to use environment variables to set the listening ports of APISIX:

```yaml title="config.yaml"
apisix:
  node_listen:
    - ${{APISIX_NODE_LISTEN:=}}
deployment:
  admin:
    admin_listen:
      port: ${{DEPLOYMENT_ADMIN_ADMIN_LISTEN:=}}
```

When you run APISIX, you can set these environment variables dynamically:

```shell
export APISIX_NODE_LISTEN=8132
export DEPLOYMENT_ADMIN_ADMIN_LISTEN=9232
```

Now when you start APISIX, it will listen on port `8132` and expose the Admin API on port `9232`.

To use default values if no environment variables are set, you can add it to your configuration file as shown below:

```yaml title="config.yaml"
apisix:
  node_listen:
    - ${{APISIX_NODE_LISTEN:=9080}}
deployment:
  admin:
    admin_listen:
      port: ${{DEPLOYMENT_ADMIN_ADMIN_LISTEN:=9180}}
```

Now if you don't specify these environment variables when running APISIX, it will fall back to the default values and expose the Admin API on port `9180` and listen on port `9080`.

## Using the `APISIX_PROFILE` environment variable

If you have multiple configuration changes for multiple environments, it might be better to have a different configuration file for each.

Although this might increase the number of configuration files, you would be able to manage each independently and can even do version management.

APISIX uses the `APISIX_PROFILE` environment variable to switch between environments, i.e. to switch between different sets of configuration files. If the value of `APISIX_PROFILE` is `env`, then APISIX will look for the configuration files `conf/config-env.yaml`, `conf/apisix-env.yaml`, and `conf/debug-env.yaml`.

For example for the production environment, you can have:

* conf/config-prod.yaml
* conf/apisix-prod.yaml
* conf/debug-prod.yaml

And for the development environment:

* conf/config-dev.yaml
* conf/apisix-dev.yaml
* conf/debug-dev.yaml

And if no environment is specified, APISIX can use the default configuration files:

* conf/config.yaml
* conf/apisix.yaml
* conf/debug.yaml

To use a particular configuration, you can specify it in the environment variable:

```shell
export APISIX_PROFILE=prod
```

APISIX will now use the `-prod.yaml` configuration files.
