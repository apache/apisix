#!/bin/bash

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


checkfunc () {
    funccontent=$1
    [[ $funccontent =~ "core.response.exit" ]] && echo "can't exit in rewrite or access phase !" && exit 1
    [[ $funccontent =~ "ngx.exit" ]] && echo "can't exit in rewrite or access phase !" && exit 1
    echo "passed."
}


filtercode () {
    content=$1

    rcontent=${content##*_M.rewrite}
    rewritefunc=${rcontent%%function*}
    checkfunc "$rewritefunc"

    rcontent=${content##*_M.access}
    accessfunc=${rcontent%%function*}
    checkfunc "$accessfunc"
}


for file in apisix/plugins/*.lua
do
    if test -f $file
    then
        echo $file
        content=$(cat $file)
        filtercode "$content"
    fi
done

# test case for check
content=$(cat t/fake-plugin-exit.lua)
filtercode "$content" > test.log 2>&1 || (cat test.log && exit 1)

echo "done."
