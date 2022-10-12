---
title: Build APISIX Dev
keywords:
  - API Gateway
  - Build APISIX Dev
description: This article describes how to quickly build a development environment for Apache APISIX with Docker and run APISIX test cases.
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

## Description

This article describes how to quickly build a development environment for Apache APISIX with Docker and run APISIX test cases.

## Introduction

By running the APISIX development environment using Docker and mounting the APISIX project directory, run the test cases in the container of the APISIX development environment. The implementation principle is as follows:

![Schematic](https://static.apiseven.com/2022/10/12/63465cd4698ba.jpg)

## Perequisites

- Make sure you have installed [Docker](https://docs.docker.com/get-docker/).
- Make sure you have installed the [make](https://docs.gitea.io/en-us/make/) command.
- Make sure you have installed the [Git](https://git-scm.com/downloads).

## Supported platform

- x86、ARM 架构
- RHEL、CentOS、Ubuntu、macOS（包括 M1、M2）、Windows 等操作系统。

## How to use

You can start the APISIX development environment on the current host and run the APISIX test case with the following steps.

### Environment preparation

1. Download APISIX and go to the APISIX directory.

    ```shell
    git clone https://github.com/apache/apisix.git
    cd apisix
    ```

2. Download the subprojects that APISIX depends on.

    ```
    git submodule update --init --recursive
    ```

    :::note

    Please execute the above command, otherwise the test case cannot be run normally.

    :::

3. Create new branch.

The following command will create a branch named `apisix-dev-test`.

    ```
    git checkout -b apisix-dev-test upstream/master
    ```

After completing the above steps, you can start to build the image of APISIX development environment.

### Build a development environment image

You can build a Docker image of the APISIX development environment with the following commands.

- For x86, run the following command:

    ```shell
    make build-dev
    ```

- For ARM, run the following command:

    ```shell
    make build-dev-arm
    ```

:::tip

After the above command is executed, an image named `apisix-dev:latest` will be created on the current host. This command only needs to be run once on the same host.

:::

If the following results are returned, the build is successful:

```shell
......
Successfully built 3224b25e55db
Successfully tagged apisix-dev:latest
```

:::note

On Windows systems, the following error may occur when executing the make command; you can ignore this prompt.

```shell
The system cannot find the path specified.
The system cannot find the path specified.
'uname' is not recognized as an internal or external command, operable program or batch file.
```

:::

### Start the development environment

The following command will start an APISIX development environment container and etcd container and download the relevant dependencies.

```shell
make run-dev
```

The returned result is as follows, indicating normal startup:

```shell
....

lua-resty-ldap 0.1.0-0 is now installed in /usr/local/apisix/deps (license: Apache License 2.0)

Stopping after installing dependencies for apisix master-0
```

### Run the test case

When running a test case, you need to specify the test case to run, either as a directory or as a separate file.

You can run a single APISIX test case with the following command:

```shell
make test-dev files=t/admin/routes.t
```

You can also run an entire directory of test cases with the following command:

```shell
make test-dev files=t/admin/
```

### Stop the development environment

After running the test case, if you do not need to use the development environment temporarily, you can run the following command to stop the container of the APISIX development environment.

```shell
make stop-dev
```

:::warning

This command removes etcd and apisix-dev containers. If you are using this container, do so with caution.

:::

## Next steps

You can refer to the following documents to develop APISIX:

- [APISIX Plugin Develop](https://apisix.apache.org/docs/apisix/plugin-develop/)
- [External Plugin](https://apisix.apache.org/zh/docs/apisix/external-plugin/)
- [APISIX Testing Framework](https://apisix.apache.org/zh/docs/apisix/internal/testing-framework/)
