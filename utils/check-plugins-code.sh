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

RED="\033[1;31m";
NC="\033[0m"; # No Color
hit=0

checkfunc () {
    funccontent=$1
    file=$2
    [[ $funccontent =~ "core.response.exit" ]] && echo -e ${RED}${file}${NC} && echo "    can't exit in rewrite or access phase!" && ((hit++))
    [[ $funccontent =~ "ngx.exit" ]] && echo -e ${RED}${file}${NC} && echo "    can't exit in rewrite or access phase!" && ((hit++))
}


filtercode () {
    content=$1
    file=$2

    rcontent=${content##*_M.rewrite}
    rewritefunc=${rcontent%%function*}
    checkfunc "$rewritefunc" "$file"

    rcontent=${content##*_M.access}
    accessfunc=${rcontent%%function*}
    checkfunc "$accessfunc" "$file"
}


for file in apisix/plugins/*.lua
do
    if test -f $file
    then
        content=$(cat $file)
        filtercode "$content" "$file"
    fi
done

if (($hit>0))
then
    exit 1
fi

# test case for check
content=$(cat t/fake-plugin-exit.lua)
filtercode "$content" > test.log 2>&1 || (cat test.log && exit 1)

echo "All passed."
