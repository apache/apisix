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

# Configuration file switching based on environment variables

The reason the configuration is extracted from the code is to better adapt to changes. Usually our applications have different
operating environments such as development environment and production environment. Certain configurations of these applications
will definitely be different, such as the address of the configuration center.

If the configuration of all environments is placed in the same file, it is very difficult to manage. After receiving new
requirements, we need to change the parameters in the configuration file to the development environment when developing the
development environment. You have to change it back. It's very easy to make mistakes.

The solution to the above problem is to distinguish the current running environment through environment variables, and switch
between different configuration files through environment variables. The corresponding environment variable in APISIX is: `APISIX_PROFILE`


When `APISIX_PROFILE` is not set, the following three configuration files are used by default:

* conf/config.yaml
* conf/apisix.yaml
* conf/debug.yaml

If the value of `APISIX_PROFILE` is set to` prod`, the following three configuration files are used:

* conf/config-prod.yaml
* conf/apisix-prod.yaml
* conf/debug-prod.yaml

Although this way will increase the number of configuration files, it can be managed independently, and then version management
tools such as git can be configured, and version management can be better achieved.
