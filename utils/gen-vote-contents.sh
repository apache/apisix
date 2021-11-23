#!/bin/sh

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
VERSION=$1
read -p "Please enter release note pr: " RELEASE_NOTE_PR
read -p "Please enter commit id: " COMMIT_ID

vote_contents="\n
Hello, Community,\n

This is a call for the vote to release Apache APISIX version $VERSION\n\n

Release notes:\n\n

$RELEASE_NOTE_PR\n\n

The release candidates:\n\n

https://dist.apache.org/repos/dist/dev/apisix/$VERSION/\n\n

Release Commit ID:\n\n

https://github.com/apache/apisix/commit/$COMMIT_ID\n\n

Keys to verify the Release Candidate:\n\n

https://dist.apache.org/repos/dist/dev/apisix/KEYS\n\n

Steps to validating the release:\n\n

1. Download the release\n\n

wget https://dist.apache.org/repos/dist/dev/apisix/$VERSION/apache-apisix-$VERSION-src.tgz\n\n

2. Checksums and signatures

wget https://dist.apache.org/repos/dist/dev/apisix/KEYS\n\n

wget https://dist.apache.org/repos/dist/dev/apisix/$VERSION/apache-apisix-$VERSION-src.tgz.asc\n\n

wget https://dist.apache.org/repos/dist/dev/apisix/$VERSION/apache-apisix-$VERSION-src.tgz.sha512\n\n

gpg --import KEYS\n\n

shasum -c apache-apisix-$VERSION-src.tgz.sha512\n\n

gpg --verify apache-apisix-$VERSION-src.tgz.asc apache-apisix-$VERSION-src.tgz\n\n

3. Unzip and Check files\n\n

tar zxvf apache-apisix-$VERSION-src.tgz\n\n

4. Build Apache APISIX:\n\n

https://github.com/apache/apisix/blob/release/$VERSION/docs/en/latest/how-to-build.md#installation-via-source-release-package\n\n

The vote will be open for at least 72 hours or until necessary number of
votes are reached.\n\n

Please vote accordingly:\n\n

[ ] +1 approve\n
[ ] +0 no opinion\n
[ ] -1 disapprove with the reason"

if [ ! -d release ];then
  mkdir release
fi
rm -rf ./release/vote-contents.txt
echo $vote_contents >> ./release/apache-apisix-$VERSION-vote-contents.txt
