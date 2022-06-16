---
title: Environment Variables
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

## Default Environment Variables

Many environment variables can be used to configure APISIX and change its behavior. Not all the environment variables are user-MODIFICABLE.

:::note
Environment variables beginning with `APISIX_` are reserved for APISIX internal usage. Do not define any environment variables with this prefix or modify them unless advised to do so.

:::

#### `APISIX_CONF_EXPIRE_TIME`

| Default | Type            | Remarks                                            |
| ------- | --------------- | -------------------------------------------------- |
| 3600s   | NON-MODIFICABLE | Only used in the multilingual plugins (ext-plugin) |

When the APISIX configuration is modified, it sends a new `PrepareConf` call to the Plugin Runner. Currently, no mechanism exists to notify the Plugin Runner of configuration change/removal. The `APISIX_CONF_EXPIRE_TIME` is a workaround to set the conf cache to expire time. The Plugin Runner caches the conf slightly longer than this environment variable value, if the configuration is still existing after the set time, a new `PrepareConf` call is sent to create a new configuration.

#### `APISIX_PROFILE`

| Default | Type        | Remarks                                                   |
| ------- | ----------- | --------------------------------------------------------- |
|         | MODIFICABLE | Used to switch configuration files based on this variable |

Usually, any APISIX instance can have multiple configuration files based on uses. They can account for multiple operating environments such as test, debug, and production. If we add the configuration in the same file, it will be very difficult to manage as well as error-prone if they are subjected to frequent changes. The `APISIX_PROFILE` variable lets us have different configuration files and switch them easily by changing the value of this variable.

Initially when this variable is not set, default configurations are used, they are:

- `conf/config.yaml`
- `conf/apisix.yaml`
- `conf/debug.yaml`

You can add multiple configuration files to the `conf` directory in the format `conf/{config or apisix or debug}-{configuration name}.yaml`. For example if `APISIX_PROFILE` is set to `test` then the files would be:

- `conf/config-test.yaml`
- `conf/apisix-test.yaml`
- `conf/debug-test.yaml`

You can add as many configuration files as you need following the same format.

#### `APISIX_LISTEN_ADDRESS`

| Default | Type        | Remarks                                                                |
| ------- | ----------- | ---------------------------------------------------------------------- |
|         | MODIFICABLE | Only used in the multilingual plugins (ext-plugin) during development. |

During development, we want to run the runner separately to avoid restating APISIX whenever we want to restart the runner. APISIX will pass the path of the Unix socket as an environment variable. The runner reads this value from `APISIX_LISTEN_ADDRESS`. By specifying this variable, we can force APISIX to listen to this specific address.

```bash
# forces the runner to listen to /tmp/x.sock.
APISIX_LISTEN_ADDRESS=unix:/tmp/x.sock ./the_runner
```

You can see how to set this address in an `ext-plugin` via the following example.

```yaml
ext-plugin:
  # cmd: ["blah"] # don't configure the executable!
  path_for_test: "/tmp/x.sock" # without 'unix:' prefix
```

### Other Variables

| Variable Name | Default | Type        | Remarks                                                                 |
| ------------- | ------- | ----------- | ----------------------------------------------------------------------- |
| `APISIX_LUA` | The relative or absolute path to [`cli/apisix.lua`](https://github.com/apache/apisix/blob/master/apisix/cli/apisix.lua) file. | NON-MODIFICABLE | Before APISIX starts, `cli/apisix.lua` does the preparation work like defining APISIX home, working directory, dependency paths, setting up startup commands, etc. |
| `APISIX_MAIN` | https://raw.githubusercontent.com/apache/incubator-apisix/master/rockspec/apisix-master-0.rockspec | NON-MODIFICABLE | The rockspec file declares the third-party libraries with their versions that are currently being used by APISIX. This can be passed as an address to the rockspec file or a link to the remote file. |
| `APISIX_ENABLE_LUACOV` | `false` | NON-MODIFICABLE | Setting this environment variable will enable the generation of Lua code coverage reports when running APISIX test cases. |
| `APISIX_PATH` | | | |
| `APISIX_WORKER_PROCESSES` | | | |

## Unused APISIX Environment Variables

These variables are not used by APISIX but are created to reference in documentation or to set testing parameters.

| Variable Name | Remarks |
| ------------- | ------- |
| `APISIX_FUZZING_PWD` | Declares the working directory for the fuzzing test. |
| `APISIX_FUZZING_LEAK_COUNT` | Only used while fuzzing test. |
| `APISIX_PERF_DURATION` | Indicates the duration of running the stress test program, only used while performance testing. |
| `APISIX_PERF_CLIENT` | Indicate the number of clients simulated by the stress test program, only used while performance testing. |
| `APISIX_PERF_THREAD` | Indicates the number of threads enabled by the stress test program, only used while performance testing. |
| `APISIX_PERF_OPS` | Indicates the constant QPS(Queries Per Second) of the stress test program, only used while performance testing. |
