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

. ./t/cli/common.sh

echo '
plugins:
    - zipkin
plugin_attr:
  zipkin:
    set_ngx_var: true
' > conf/config.yaml

make init

if ! grep "set \$zipkin_context_traceparent          '';" conf/nginx.conf > /dev/null; then
    echo "failed: zipkin_context_traceparent not found in nginx.conf"
    exit 1
fi

if ! grep "set \$zipkin_trace_id                     '';" conf/nginx.conf > /dev/null; then
    echo "failed: zipkin_trace_id not found in nginx.conf"
    exit 1
fi

if ! grep "set \$zipkin_span_id                      '';" conf/nginx.conf > /dev/null; then
    echo "failed: zipkin_span_id not found in nginx.conf"
    exit 1
fi


echo "passed: zipkin_set_ngx_var configuration is validated"
