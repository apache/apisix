#!/usr/bin/env bash
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

test_type=$1

echo "started backing up, time: $(date)"
mkdir docker-images-backup
sum=$(cat ci/pod/docker-compose.$test_type.yml | grep image | wc -l)
special_tag=$(cat ci/pod/docker-compose.$test_type.yml | grep image: | awk '{print $2}' | awk 'ORS=NR%"'$sum'"?" ":"\n"{print}')
echo special: $special_tag
openwhisk_tag="openwhisk/action-nodejs-v14:nightly openwhisk/standalone:nightly"
echo
echo special_tag: $special_tag
echo openwhisk_tag: $openwhisk_tag
echo
all_tags="${special_tag} ${openwhisk_tag}"
to_pull=""

for tag in $all_tags
do
    if ! ( docker inspect $tag &> /dev/null )
    then
        to_pull="${to_pull} ${tag}"
    fi
done

echo to pull : $to_pull

if [[ -n $to_pull ]]
then
    echo "$to_pull" | xargs -P10 -n1 docker pull
fi

docker save $special_tag $openwhisk_tag -o docker-images-backup/apisix-images.tar
echo "docker save done, time: $(date)"
