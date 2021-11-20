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

1. Create a pull request (contains the changelog and version change) to master, merge it
2. Create a pull request (contains the backport commits, and the change in step 1) to minor branch
3. Merge it into minor branch
4. Package a vote artifact to Apache's dev-apisix repo. The artifact can be created
via `VERSION=x.y.z make release-src`
5. Send the vote email to dev@apisix.apache.org
6. When the vote is passed, send the vote result email to dev@apisix.apache.org
7. Move the vote artifact to Apache's apisix repo
8. Create a GitHub release from the minor branch
9. Update [APISIX's website](https://github.com/apache/apisix-website/blob/master/website/docusaurus.config.js#L110-L123)
10. Update APISIX docker
11. Update APISIX rpm package
12. Send the [ANNOUNCE email](https://lists.apache.org/thread.html/ree7b06e6eac854fd42ba4f302079661a172f514a92aca2ef2f1aa7bb%40%3Cdev.apisix.apache.org%3E) to dev@apisix.apache.org & announce@apache.org

### Release minor version

1. Create a minor branch, and create pull request to master branch from it
2. Package a vote artifact to Apache's dev-apisix repo. The artifact can be created
via `VERSION=x.y.z make release-src`
3. Send the vote email to dev@apisix.apache.org
4. When the vote is passed, send the vote result email to dev@apisix.apache.org
5. Move the vote artifact to Apache's apisix repo
6. Create a GitHub release from the minor branch
7. Merge the pull request into master branch
8. Update APISIX website
9. Update APISIX docker
10. Update APISIX rpm package
11. Send the ANNOUNCE email to dev@apisix.apache.org & announce@apache.org
