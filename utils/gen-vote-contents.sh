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

SUBSTRING1=$(echo $VERSION| cut -d'.' -f 1)
SUBSTRING2=$(echo $VERSION| cut -d'.' -f 2)
BLOB_VERSION=$SUBSTRING1.$SUBSTRING2
CHANGELOG_HASH=$(printf $VERSION | sed 's/\.//g')

RELEASE_NOTE_PR="https://github.com/apache/apisix/blob/release/$BLOB_VERSION/CHANGELOG.md#$CHANGELOG_HASH"
COMMIT_ID=$(git rev-parse --short HEAD)

vote_contents=$(cat <<EOF
Hello, Community,

This is a call for the vote to release Apache APISIX version

Release notes:

$RELEASE_NOTE_PR

The release candidates:

https://dist.apache.org/repos/dist/dev/apisix/$VERSION/

Release Commit ID:

https://github.com/apache/apisix/commit/$COMMIT_ID

Keys to verify the Release Candidate:

https://dist.apache.org/repos/dist/dev/apisix/KEYS

Steps to validating the release:

1. Download the release

wget https://dist.apache.org/repos/dist/dev/apisix/$VERSION/apache-apisix-$VERSION-src.tgz

2. Checksums and signatures

wget https://dist.apache.org/repos/dist/dev/apisix/KEYS

wget https://dist.apache.org/repos/dist/dev/apisix/$VERSION/apache-apisix-$VERSION-src.tgz.asc

wget https://dist.apache.org/repos/dist/dev/apisix/$VERSION/apache-apisix-$VERSION-src.tgz.sha512

gpg --import KEYS

shasum -c apache-apisix-$VERSION-src.tgz.sha512

gpg --verify apache-apisix-$VERSION-src.tgz.asc apache-apisix-$VERSION-src.tgz

3. Unzip and Check files

tar zxvf apache-apisix-$VERSION-src.tgz

4. Build Apache APISIX:

https://github.com/apache/apisix/blob/release/$BLOB_VERSION/docs/en/latest/building-apisix.md#building-apisix-from-source

The vote will be open for at least 72 hours or until necessary number of
votes are reached.

Please vote accordingly:

[ ] +1 approve
[ ] +0 no opinion
[ ] -1 disapprove with the reason
EOF
)

if [ ! -d release ];then
  mkdir release
fi

printf "$vote_contents" > ./release/apache-apisix-$VERSION-vote-contents.txt
