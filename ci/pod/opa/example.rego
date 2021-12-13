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
package example

import input.request

default allow = false

allow {
    request.headers["test-header"] == "only-for-test"
    request.method == "GET"
    startswith(request.path, "/hello")
    request.query["test"] != "abcd"
}

reason = {"code": 40001, "desc": "wrong request"} {
    not allow
    not request.query["user"]
}

headers = {
    "test": "abcd"
} {
    not allow
    not request.query["user"]
}

headers = {
    "Location": "http://example.com/auth"
} {
    not allow
    request.query["user"]
}

status_code = 204 {
    not allow
    not request.query["user"]
}

status_code = 302 {
    not allow
    request.query["user"]
}
