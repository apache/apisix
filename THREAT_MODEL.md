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

## Threat Model

Here is the threat model of Apache APISIX, which is relative to our developers and operators.

### Where the system might be attacked

As a proxy, Apache APISIX needs to be able to run in front of untrusted downstream traffic.

However, some features need to assume the downstream traffic is trusted. They should be either
not exposed to the internet by default (for example, listening to 127.0.0.1), or disclaim in
the doc explicitly.

As Apache APISIX is evolving rapidly, some newly added features may not be strong enough to defend against potential attacks.
Therefore, we need to divide the features into two groups: premature and mature ones.
Features that are just merged in half a year or are declared as experimental are premature.
Premature features are not fully tested on the battlefield and are not covered by the security policy normally.

Additionally, we require the components below are trustable:

1. the upstream
2. the configuration
3. the way we relay the configuration
4. the 3rd party components involved in the Apache APISIX, for example, the authorization server

### How can we reduce the likelihood or impact of a potential threat

As the user:
First of all, don't expose the components which are required to be trustable to the internet, including the control plane (Dashboard or something else) and the configuration relay mechanism (etcd or etcd adapter or something else).

Then, harden the trusted components. For example,

1. if possible, enable authentication or use https for the etcd
2. read the doc and disable plugins that are not needed, so that we can reduce the attack vector
3. restrict and audit the change of configuration

As the developer:
We should keep security in mind, and validate the input from the client before use.

As the maintainer:
We should keep security in mind, and review the code line by line.
We are open to discussion from the security researchers.
