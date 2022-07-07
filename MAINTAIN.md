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

## Release steps

### Release patch version

1. Create a [pull request](https://github.com/apache/apisix/commit/7db31a1a7186b966bc0f066539d4de8011871012) (contains the changelog and version change) to master
   > The changelog only needs to provide a link to the minor branch.
2. Create a [pull request](https://github.com/apache/apisix/commit/21d7673c6e8ff995677456cdebc8ded5afbb3d0a) (contains the backport commits, and the change in step 1) to minor branch
   > This should include those PRs that contain the `need backport` tag since the last patch release. Also, the title of these PRs need to be added to the changelog of the minor branch.
3. Merge it into minor branch
4. Package a vote artifact to Apache's dev-apisix repo. The artifact can be created via `VERSION=x.y.z make release-src`
5. Send the [vote email](https://lists.apache.org/thread/vq4qtwqro5zowpdqhx51oznbjy87w9d0) to dev@apisix.apache.org
   > After executing the `VERSION=x.y.z make release-src` command, the content of the vote email will be automatically generated in the `./release` directory named `apache-apisix-${x.y.z}-vote-contents`
6. When the vote is passed, send the [vote result email](https://lists.apache.org/thread/k2frnvj4zj9oynsbr7h7nd6n6m3q5p89) to dev@apisix.apache.org
7. Move the vote artifact to Apache's apisix repo
8. Register the release info in https://reporter.apache.org/addrelease.html?apisix
9. Create a [GitHub release](https://github.com/apache/apisix/releases/tag/2.10.2) from the minor branch
10. Update [APISIX's website](https://github.com/apache/apisix-website/commit/f9104bdca50015722ab6e3714bbcd2d17e5c5bb3) if the version number is the largest
11. Update APISIX rpm package
    > Go to [apisix-build-tools](https://github.com/api7/apisix-build-tools) repository and create a new tag named `apisix-${x.y.z}` to automatically submit the
    package to yum repo
12. - If the version number is the largest, update [APISIX docker](https://github.com/apache/apisix-docker/commit/829d45559c303bea7edde5bebe9fcf4938071601) in [APISIX docker repository](https://github.com/apache/apisix-docker), after PR merged, then create a new branch from master, named as `release/apisix-${version}`, e.g. `release/apisix-2.10.2`.
    - If released an LTS version and the version number less than the current largest(e.g. the current largest version number is 2.14.1, but the LTS version 2.13.2 is to be released), submit a PR like [APISIX docker](https://github.com/apache/apisix-docker/pull/322) in [APISIX docker repository](https://github.com/apache/apisix-docker) and named as `release/apisix-${version}`, e.g. `release/apisix-2.13.2`, after PR reviewed, don't need to merged PR, just close the PR and push the branch to APISIX docker repository.
13. Update [APISIX helm chart](https://github.com/apache/apisix-helm-chart/pull/234) if the version number is the largest
14. Send the [ANNOUNCE email](https://lists.apache.org/thread.html/ree7b06e6eac854fd42ba4f302079661a172f514a92aca2ef2f1aa7bb%40%3Cdev.apisix.apache.org%3E) to dev@apisix.apache.org & announce@apache.org

### Release minor version

1. Create a minor branch, and create [pull request](https://github.com/apache/apisix/commit/bc6ddf51f15e41fffea6c5bd7d01da9838142b66) to master branch from it
2. Package a vote artifact to Apache's dev-apisix repo. The artifact can be created via `VERSION=x.y.z make release-src`
3. Send the [vote email](https://lists.apache.org/thread/q8zq276o20r5r9qjkg074nfzb77xwry9) to dev@apisix.apache.org
   > After executing the `VERSION=x.y.z make release-src` command, the content of the vote email will be automatically generated in the `./release` directory named `apache-apisix-${x.y.z}-vote-contents`
4. When the vote is passed, send the [vote result email](https://lists.apache.org/thread/p1m9s116rojlhb91g38cj8646393qkz7) to dev@apisix.apache.org
5. Move the vote artifact to Apache's apisix repo
6. Register the release info in https://reporter.apache.org/addrelease.html?apisix
7. Create a [GitHub release](https://github.com/apache/apisix/releases/tag/2.10.0) from the minor branch
8. Merge the pull request into master branch
9. Update [APISIX's website](https://github.com/apache/apisix-website/commit/7bf0ab5a1bbd795e6571c4bb89a6e646115e7ca3)
10. Update APISIX rpm package.
    > Go to [apisix-build-tools](https://github.com/api7/apisix-build-tools) repository and create a new tag named `apisix-${x.y.z}` to automatically submit the rpm package to yum repo
11. - If the version number is the largest, update [APISIX docker](https://github.com/apache/apisix-docker/commit/829d45559c303bea7edde5bebe9fcf4938071601) in [APISIX docker repository](https://github.com/apache/apisix-docker), after PR merged, then create a new branch from master, named as `release/apisix-${version}`, e.g. `release/apisix-2.10.2`.
    - If released an LTS version and the version number less than the current largest(e.g. the current largest version number is 2.14.1, but the LTS version 2.13.2 is to be released), submit a PR like [APISIX docker](https://github.com/apache/apisix-docker/pull/322) in [APISIX docker repository](https://github.com/apache/apisix-docker) and named as `release/apisix-${version}`, e.g. `release/apisix-2.13.2`, after PR reviewed, don't need to merged PR, just close the PR and push the branch to APISIX docker repository.
12. Update [APISIX helm chart](https://github.com/apache/apisix-helm-chart/pull/234)
13. Send the [ANNOUNCE email](https://lists.apache.org/thread/4s4msqwl1tq13p9dnv3hx7skbgpkozw1) to dev@apisix.apache.org & announce@apache.org
