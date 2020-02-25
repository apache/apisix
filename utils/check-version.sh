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

ver=$1

red='\e[0;41m'
RED='\e[1;31m'
green='\e[0;32m'
GREEN='\e[1;32m'
NC='\e[0m'

# doc: apisix $ver
matched=`grep "apisix.[0-9][0-9.]*" -r doc/`
expected=`grep "apisix.$ver" -r doc/`

if [ "$matched" = "$expected" ]; then
    echo -e "${green}passed: (doc) apisix $ver ${NC}"
else
    echo -e "${RED}failed: (doc) apisix $ver ${NC}" 1>&2
    echo
    echo "-----maybe wrong version-----"
    echo "$matched"
    exit 1
fi

# doc: version $ver
matched=`grep "version [0-9][0-9.]*" -r doc/`
expected=`grep -F "version $ver" -r doc/`

if [ "$matched" = "$expected" ]; then
    echo -e "${green}passed: (doc) version $ver ${NC}"
else
    echo -e "${RED}failed: (doc) version $ver ${NC}" 1>&2
    echo
    echo "-----maybe wrong version-----"
    echo "$matched"
    exit 1
fi

# lua: VERSION = $ver
matched=`grep "VERSION = \"[0-9][0-9.]*\"" -r lua/`
expected=`grep -F "VERSION = \"$ver\"" -r lua/`

if [ "$matched" = "$expected" ]; then
    echo -e "${green}passed: (lua) VERSION = $ver ${NC}"
else
    echo -e "${RED}failed: (lua) VERSION = \"$ver\" ${NC}" 1>&2
    echo
    echo "-----maybe wrong version-----"
    echo "$matched"
    exit 1
fi


# rockspec
matched=`ls -l rockspec/ | grep  "$ver" `

if [ !$matched ]; then
    echo -e "${RED}failed: (rockspec) VERSION = $ver \"$ver\" ${NC}" 1>&2
    echo
    echo "-----please check rockspec file for VERSION \"$ver\"-----"
    echo "$matched"
    exit 1
else
    echo -e "${green}passed: (rockspec) VERSION = $ver ${NC}"
fi
