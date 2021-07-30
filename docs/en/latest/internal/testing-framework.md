---
title: Introducing APISIX's testing framework
---

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

APISIX uses a testing framework based on our fork of test-nginx: https://github.com/iresty/test-nginx.
For details, you can check the documentation of this project.

If you want to test the CLI behavior of APISIX (`./bin/apisix`),
you need to write a shell script in the t/cli directory to test it. You can refer to the existing test scripts for more details.

If you want to test the others, you need to write test code based on the framework.

Here, we briefly describe how to do simple testing based on this framework.

## Test file

you need to write test cases in the t/ directory, in a corresponding `.t` file. Note that a single test file should not exceed `800` lines, and if it is too long, it needs to be divided by a suffix. For example:

```
t/
├── admin
│ ├── consumers.t
│ ├── consumers2.t
```

Both `consumers.t` and `consumers2.t` contain tests for consumers in the Admin API.

Some of the test files start with this paragraph:

```
add_block_preprocessor(sub {
    my ($block) = @_;

    if (! $block->request) {
        $block->set_value("request", "GET /t");
    }

    if (! $block->no_error_log && ! $block->error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});
```

It means that all tests in this test file that do not define `request` are set to `GET /t`. The same is true for error_log.

## Preparing the configuration

When testing a behavior, we need to prepare the configuration.

If the configuration is from etcd:
We can set up specific configurations through the Admin API.

```
=== TEST 7: refer to empty nodes upstream
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code, message = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "methods": ["GET"],
                    "upstream_id": "1",
                    "uri": "/index.html"
                }]]
                )

            if code >= 300 then
                ngx.status = code
                ngx.print(message)
                return
            end

            ngx.say(message)
        }
    }
--- request
GET /t
--- response_body
passed
```

Then trigger it in a later test:

```
=== TEST 8: hit empty nodes upstream
--- request
GET /index.html
--- error_code: 503
--- error_log
no valid upstream node
```

## Send request

We can initiate a request with `request` and set the request headers with `more_headers`.

For example.

```
--- request
PUT /hello?xx=y&xx=z&&y=&&z
body part of the request
--- more_headers
X-Req: foo
X-Req: bar
X-Resp: cat
```

Lua code can be used to send multiple requests.

One request after another:

```
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" ... ngx.var.server_port
                        ... "/server_port"

            local ports_count = {}
            for i = 1, 12 do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri, {method = "GET"})
                if not res then
                    ngx.say(err)
                    return
                end
                ports_count[res.body] = (ports_count[res.body] or 0) + 1
            end

```

Sending multiple requests concurrently:

```
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" ... ngx.var.server_port
                        ... "/server_port?var=2&var2="


            local t = {}
            local ports_count = {}
            for i = 1, 180 do
                local th = assert(ngx.thread.spawn(function(i))
                    local httpc = http.new()
                    local res, err = httpc:request_uri(uri..i, {method = "GET"})
                    if not res then
                        ngx.log(ngx.ERR, err)
                        return
                    end
                    ports_count[res.body] = (ports_count[res.body] or 0) + 1
                end, i))
                table.insert(t, th)
            end
            for i, th in ipairs(t) do
                ngx.thread.wait(th)
            end
```

## Assertions

The following assertions are commonly used.

Check status (if not set, the framework will check if the request has 200 status code).

```
--- error_code: 405
```

Check response headers.

```
--- response_headers
X-Resp: foo
X-Req: foo, bar
```

Check response body.

```
--- response_body
[{"count":12, "port": "1982"}]
```

Checking the error log (via grep error log with regular expression).

```
--- grep_error_log eval
qr/hash_on: header|chash_key: "custom-one"/
--- grep_error_log_out
hash_on: header
chash_key: "custom-one"
hash_on: header
chash_key: "custom-one"
hash_on: header
chash_key: "custom-one"
hash_on: header
chash_key: "custom-one"
```

The default log level is `info`, but you can get the debug level log with `-- log_level: debug`.

## Upstream

The test framework listens to multiple ports when it is started.

* 1980/1981/1982/5044: HTTP upstream port
* 1983: HTTPS upstream port
* 1984: APISIX HTTP port. Can be used to verify HTTP related gateway logic, such as concurrent access to an API.
* 1994: APISIX HTTPS port. Can be used to verify HTTPS related gateway logic, such as testing certificate matching logic.

The methods in `t/lib/server.lua` are executed when accessing the upstream port. `_M.go` is the entry point for this file.
When the request accesses the upstream `/xxx`, the `_M.xxx` method is executed. For example, a request for `/hello` will execute `_M.hello`.
This allows us to write methods inside `t/lib/server.lua` to emulate specific upstream logic, such as sending special responses.

Note that before adding new methods to `t/lib/server.lua`, make sure that you can reuse existing methods.

## Run the test

Assume your current work directory is the root of the apisix source code.

1. Install our fork of [test-nginx](https://github.com/iresty/test-nginx) to `../test-nginx`.
2. Run the test: `prove -I. -I../test-nginx/inc -I../test-nginx/lib -r t/path/to/file.t`.

## Tips

### Debugging test cases

The Nginx configuration and logs generated by the test cases are located in the t/servroot directory. The Nginx configuration template for testing is located in t/APISIX.pm.

### Running only some test cases

Three notes can be used to control which parts of the tests are executed.

FIRST & LAST:

```
=== TEST 1: vars rule with ! (set)
--- FIRST
--- config
...
--- response_body
passed



=== TEST 2: vars rule with ! (hit)
--- request
GET /hello?name=jack&age=17
--- LAST
--- error_code: 403
--- response_body
Fault Injection!
```

ONLY:

```
=== TEST 1: list empty resources
--- ONLY
--- config
...
--- response_body
{"action":"get","count":0,"node":{"dir":true,"key":"/apisix/upstreams","nodes":{}}}
```
